# Databricks notebook source
# MAGIC %md
# MAGIC # Recorded discount actors and weekly opportunity coverage
# MAGIC Positive actions use their recorded actor. First-payment ownership is an
# MAGIC opportunity proxy. Unknown actors, incomplete amounts and calendar gaps remain explicit.

# COMMAND ----------
import json,sys
from pathlib import Path
from pyspark.sql import functions as F
for name in ('repo_root','catalog','model_schema','expected_owner','model_run_id','facts_table','events_table','payments_table'):
    dbutils.widgets.text(name,'')
root=Path(dbutils.widgets.get('repo_root'))
if not root.is_absolute():raise ValueError('Absolute deployed repo_root required')
sys.path.insert(0,str(root/'src/models'))
from workspace_runtime import Workspace,run_identifier,fingerprint
c=Workspace(spark,dbutils.widgets.get('catalog'),dbutils.widgets.get('model_schema'),dbutils.widgets.get('expected_owner'))
run=run_identifier(dbutils.widgets.get('model_run_id'))
code_hash=fingerprint([(n,(root/'src/models'/n).read_text(encoding='utf-8')) for n in ('actor_checks.sql','actor_week_history.sql')])
c.ensure_schema()
if spark.catalog.tableExists(c.table('actor_model_runs')):
    completed=spark.table(c.table('actor_model_runs')).where(F.col('model_run_id')==run).collect()
    if len(completed)==1:
        if completed[0].code_sha256!=code_hash:raise ValueError('Completed actor run has different code; use a new run ID')
        dbutils.notebook.exit(json.dumps({'status':'already_completed','model_run_id':run}))
    if completed:raise ValueError('Ambiguous actor completion')
refs={};snapshots={}
for key,widget in [('facts','facts_table'),('events','events_table'),('payments','payments_table')]:
    refs[key],snapshots[key]=c.frozen_source(dbutils.widgets.get(widget))
if spark.catalog.tableExists(c.table('actor_run_inputs')):
    old=spark.table(c.table('actor_run_inputs')).where(F.col('model_run_id')==run).collect()
    if old:
        if len(old)!=1 or old[0].code_sha256!=code_hash:raise ValueError('Ambiguous actor run input or changed retry code')
        snapshots=json.loads(old[0].source_versions_json)
        refs={k:f"{v['table']} VERSION AS OF {int(v['version'])}" for k,v in snapshots.items()}
c.append('actor_run_inputs',spark.createDataFrame([dict(model_run_id=run,source_versions_json=json.dumps(snapshots,sort_keys=True),code_sha256=code_hash)]),run)
checks=spark.sql((root/'src/models/actor_checks.sql').read_text(encoding='utf-8').format(**refs))
checks.createOrReplaceTempView('actor_checks')
weekly=spark.sql((root/'src/models/actor_week_history.sql').read_text(encoding='utf-8').format(**refs))
weekly=weekly.withColumn('model_run_id',F.lit(run)).withColumn('source_versions_json',F.lit(json.dumps(snapshots,sort_keys=True)))
count=weekly.count()
if not count or weekly.select('employee_id','location_id','week_start').distinct().count()!=count:
    raise ValueError('Actor-week uniqueness or empty-input failure')
c.append('actor_week_history',weekly,run)
if spark.table(c.table('actor_week_history')).where(F.col('model_run_id')==run).count()!=count:
    raise ValueError('Actor persistence count mismatch')
manifest=spark.createDataFrame([dict(model_run_id=run,status='completed',weekly_rows=count,source_versions_json=json.dumps(snapshots,sort_keys=True),code_sha256=code_hash)]).withColumn('completed_at',F.current_timestamp())
c.append('actor_model_runs',manifest,run)
dbutils.notebook.exit(json.dumps({'status':'completed','model_run_id':run,'weekly_rows':count}))
