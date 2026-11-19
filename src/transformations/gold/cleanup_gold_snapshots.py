# Databricks notebook source
# MAGIC %md
# MAGIC # Keep only the latest Gold snapshot
# MAGIC Every Job run copies Silver into a new `<gold_schema>_<hash>` schema. Old copies are not needed once the run has
# MAGIC finished, and the workspace has a table limit, so this last task drops every older snapshot schema.
# MAGIC It only touches schemas that match the snapshot name pattern, carry this project's marker comment and are owned
# MAGIC by the configured owner. The current run's snapshot is always kept.

# COMMAND ----------
import json,re,sys
from pathlib import Path
for name in ('repo_root','catalog','gold_schema','expected_owner','gold_namespace'):
    dbutils.widgets.text(name,'')
root=Path(dbutils.widgets.get('repo_root'))
if not root.is_absolute():raise ValueError('Absolute deployed repo_root required')
sys.path.insert(0,str(root/'src/models'))
from workspace_runtime import MARKER,identifier
catalog=identifier(dbutils.widgets.get('catalog'))
prefix=identifier(dbutils.widgets.get('gold_schema'))
owner=dbutils.widgets.get('expected_owner')
current=identifier(dbutils.widgets.get('gold_namespace'),2)
if not current.startswith(catalog+'.'):raise ValueError('Current snapshot is outside the configured catalog')
keep=current.split('.',1)[1]
if spark.sql('SELECT current_user()').first()[0]!=owner:raise ValueError('Executing identity differs from configured expected_owner')
pattern=re.compile(re.escape(prefix)+r'_[0-9a-f]{12}')
rows=spark.sql(f"SELECT schema_name,schema_owner,comment FROM {catalog}.information_schema.schemata").collect()
if keep not in {r.schema_name for r in rows}:raise ValueError('Current snapshot schema not found; nothing dropped')
dropped,skipped=[],[]
for r in rows:
    if r.schema_name==keep or not pattern.fullmatch(r.schema_name):continue
    if r.schema_owner!=owner or r.comment!=MARKER:
        skipped.append(r.schema_name);continue
    spark.sql(f'DROP SCHEMA {catalog}.{identifier(r.schema_name)} CASCADE')
    dropped.append(r.schema_name)
dbutils.notebook.exit(json.dumps({'status':'completed','kept':keep,'dropped':dropped,'skipped_not_owned':skipped}))
