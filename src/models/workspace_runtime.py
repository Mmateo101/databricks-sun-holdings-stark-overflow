"""Portable Databricks boundaries: configured namespaces and fail-closed ownership."""
import hashlib
import json
import re

MARKER = 'stark-overflow-model-v1'

def identifier(value, parts=1):
    if not isinstance(value,str) or not re.fullmatch(r'[A-Za-z_][A-Za-z0-9_]*(?:\.[A-Za-z_][A-Za-z0-9_]*){'+str(parts-1)+'}',value):
        raise ValueError('Expected a safe '+str(parts)+'-part SQL identifier')
    return value

def run_identifier(value):
    if not isinstance(value,str) or not re.fullmatch(r'[A-Za-z0-9_-]{1,100}',value):
        raise ValueError('Safe nonempty run identifier required')
    return value

class Workspace:
    def __init__(self,spark,catalog,schema,expected_owner,require_executor=True):
        self.spark=spark
        self.catalog=identifier(catalog);self.schema=identifier(schema)
        self.namespace=f'{self.catalog}.{self.schema}'
        self.executor=spark.sql('SELECT current_user()').first()[0]
        self.owner=expected_owner
        if not expected_owner or (require_executor and self.executor!=expected_owner):
            raise ValueError('Executing identity differs from configured expected_owner')

    def ensure_schema(self):
        rows=self.spark.sql(f"SELECT schema_owner,comment FROM {self.catalog}.information_schema.schemata WHERE schema_name='{self.schema}'").collect()
        if rows:
            if len(rows)!=1 or rows[0].schema_owner!=self.owner or rows[0].comment!=MARKER:
                raise ValueError('Refusing an unrecognized or foreign output schema')
        else:
            if self.executor!=self.owner:raise ValueError('Only the configured owner creates the output schema')
            self.spark.sql(f"CREATE SCHEMA {self.namespace} COMMENT '{MARKER}'")

    def table(self,name):return self.namespace+'.'+identifier(name)

    def ensure_table(self,name,frame=None,ddl=None):
        self.ensure_schema()
        name=identifier(name)
        rows=self.spark.sql(f"SELECT table_owner,comment FROM {self.catalog}.information_schema.tables WHERE table_schema='{self.schema}' AND table_name='{name}'").collect()
        if rows:
            if len(rows)!=1 or rows[0].table_owner!=self.owner or rows[0].comment!=MARKER:
                raise ValueError('Refusing an unrecognized or foreign output table')
        else:
            if self.executor!=self.owner:raise ValueError('Only the configured owner creates output tables')
            if ddl is None:ddl=', '.join(f'`{f.name}` {f.dataType.simpleString()}' for f in frame.schema.fields)
            self.spark.sql(f"CREATE TABLE {self.table(name)} ({ddl}) USING DELTA COMMENT '{MARKER}'")

    def append(self,name,frame,key):
        self.ensure_table(name,frame)
        (frame.write.format('delta').mode('append').option('txnAppId',self.table(name)+':'+run_identifier(key))
         .option('txnVersion',0).saveAsTable(self.table(name)))

    def frozen_source(self,table):
        table=identifier(table,3)
        version=int(self.spark.sql(f'DESCRIBE HISTORY {table} LIMIT 1').first().version)
        return f'{table} VERSION AS OF {version}',{'table':table,'version':version}

def fingerprint(value):
    return hashlib.sha256(json.dumps(value,sort_keys=True,default=str,separators=(',',':')).encode()).hexdigest()
