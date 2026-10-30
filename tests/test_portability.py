import importlib.util
import io
import os
from pathlib import Path
import sys
import tempfile
import unittest
from unittest.mock import patch
ROOT=Path(__file__).resolve().parents[1]
sys.path.insert(0,str(ROOT/'src/models'))
from workspace_runtime import Workspace,identifier,run_identifier
spec=importlib.util.spec_from_file_location('sql_runner',ROOT/'tools/run_sql.py')
runner=importlib.util.module_from_spec(spec);spec.loader.exec_module(runner)

class Result:
    def __init__(self,rows):self.rows=rows
    def first(self):return self.rows[0] if self.rows else None
    def collect(self):return self.rows

class FakeSpark:
    def __init__(self,owner='owner@example.invalid',schema_owner=None):self.owner=owner;self.schema_owner=schema_owner;self.calls=[]
    def sql(self,sql):
        self.calls.append(sql)
        if sql=='SELECT current_user()':return Result([[self.owner]])
        if 'information_schema.schemata' in sql:
            return Result([] if self.schema_owner is None else [type('Meta',(),{'schema_owner':self.schema_owner,'comment':'stark-overflow-model-v1'})()])
        return Result([])

class PortabilityTests(unittest.TestCase):
    def test_identifiers_refuse_sql_injection(self):
        self.assertEqual(identifier('catalog.schema.table',3),'catalog.schema.table')
        for value in ['a;DROP TABLE x','a b','a.b','../private']:
            with self.assertRaises(ValueError):identifier(value)
        with self.assertRaises(ValueError):run_identifier("run'; DELETE")

    def test_foreign_identity_or_schema_is_refused(self):
        with self.assertRaises(ValueError):Workspace(FakeSpark(),'cat','out','someone_else')
        spark=FakeSpark(schema_owner='other@example.invalid')
        with self.assertRaises(ValueError):Workspace(spark,'cat','out',spark.owner).ensure_schema()
        self.assertFalse(any(s.startswith('CREATE') for s in spark.calls))

    def test_reviewer_cannot_create_schema_under_other_owner(self):
        spark=FakeSpark(owner='reviewer@example.invalid')
        c=Workspace(spark,'cat','out','owner@example.invalid',require_executor=False)
        with self.assertRaises(ValueError):c.ensure_schema()

    def test_sql_parser_handles_quoted_semicolons_and_comments(self):
        with tempfile.TemporaryDirectory() as d:
            p=Path(d)/'script.sql';p.write_text("-- comment\nSELECT 'a;b', 'can''t'; /* ; */ SELECT 2;")
            self.assertEqual(runner.statements(p),["SELECT 'a;b', 'can''t'",'SELECT 2'])
            p.write_text("CREATE VIEW demo WITH METRICS LANGUAGE YAML AS $$\ncomment: an employee's item; unchanged\n$$; SELECT 2;")
            parsed=runner.statements(p)
            self.assertEqual(len(parsed),2)
            self.assertIn("employee's item; unchanged",parsed[0])
            p.write_text("SELECT 'unfinished")
            with self.assertRaises(ValueError):runner.statements(p)

    def test_render_missing_or_unsafe_values_refused(self):
        self.assertEqual(runner.render('SELECT * FROM ${catalog}.gold.t',{'catalog':'demo'}),'SELECT * FROM demo.gold.t')
        with self.assertRaises(ValueError):runner.render('SELECT ${unknown}',{})
        with self.assertRaises(ValueError):runner.render('SELECT ${catalog}',{'catalog':'a;bad'})

    def test_dry_run_needs_no_credentials_or_warehouse(self):
        with patch.dict(os.environ,{},clear=True),patch.object(runner,'execute',side_effect=AssertionError('network forbidden')),patch('sys.stdout',new_callable=io.StringIO):
            with patch.object(sys,'argv',['run_sql.py',str(ROOT/'src/semantic/02_gold_copy.sql'),'--dry-run','--var','source_gold_schema=demo.gold']):
                runner.main()

    def test_live_execution_requires_warehouse_before_api(self):
        with patch.dict(os.environ,{},clear=True),patch.object(runner,'api',side_effect=AssertionError('network forbidden')):
            with self.assertRaises(ValueError):runner.execute('SELECT 1')

if __name__=='__main__':unittest.main()
