# Databricks notebook source
# MAGIC %md
# MAGIC # Weekly review list
# MAGIC Joins the Bayesian model (employee vs. their store) and the time series (employee vs. their own history) into
# MAGIC one row per employee and week with a priority and the reasons in plain words. This is what the weekly report shows.
# MAGIC A priority means "review first", not proof of fraud.

# COMMAND ----------
import json,sys
from pathlib import Path
from pyspark.sql import functions as F
for name in ('repo_root','catalog','model_schema','expected_owner','model_run_id','gold_namespace'):
    dbutils.widgets.text(name,'')
root=Path(dbutils.widgets.get('repo_root'))
if not root.is_absolute():raise ValueError('Absolute deployed repo_root required')
sys.path.insert(0,str(root/'src/models'))
from workspace_runtime import Workspace,identifier,run_identifier,fingerprint
c=Workspace(spark,dbutils.widgets.get('catalog'),dbutils.widgets.get('model_schema'),dbutils.widgets.get('expected_owner'))
run=run_identifier(dbutils.widgets.get('model_run_id'))
gold=identifier(dbutils.widgets.get('gold_namespace'),2)
sql_text=(root/'src/models/review_list.sql').read_text(encoding='utf-8')
code_hash=fingerprint([('review_list.sql',sql_text),('build_review_list.py',(root/'src/models/build_review_list.py').read_text(encoding='utf-8')),('gold',gold)])
c.ensure_schema()
if spark.catalog.tableExists(c.table('review_list_runs')):
    old=spark.table(c.table('review_list_runs')).where(F.col('model_run_id')==run).collect()
    if len(old)==1:
        if old[0].code_sha256!=code_hash:raise ValueError('Completed review list identity changed; use a new run ID')
        dbutils.notebook.exit(json.dumps({'status':'already_completed','model_run_id':run}))
    if old:raise ValueError('Ambiguous review list completion')
for name in ('scenario_model_runs','ts_model_runs'):
    if spark.table(c.table(name)).where((F.col('model_run_id')==run)&(F.col('status')=='completed')).count()!=1:
        raise ValueError('Model and time series must both be completed for this run: '+name)

# COMMAND ----------
sql=sql_text.replace('{{model}}',c.namespace).replace('{{gold}}',gold).replace('{{run}}',run)
if '{{' in sql:raise ValueError('Unresolved review list template')
frame=spark.sql(sql).withColumn('model_run_id',F.lit(run))
rows=frame.count()
if rows!=frame.select('employee_id','location_id','week_start').distinct().count():raise ValueError('Review list grain mismatch')
c.append('review_list_week',frame,run)
latest=frame.agg(F.max('week_start')).first()[0]
counts={str(r.priority):r['count'] for r in frame.where((F.col('week_start')==latest)&F.col('priority').isNotNull()).groupBy('priority').count().collect()}
c.append('review_list_runs',spark.createDataFrame([dict(model_run_id=run,status='completed',code_sha256=code_hash,rows=rows,
  latest_week=str(latest),latest_week_counts_json=json.dumps(counts,sort_keys=True))]).withColumn('completed_at',F.current_timestamp()),run)
dbutils.notebook.exit(json.dumps({'status':'completed','model_run_id':run,'rows':rows,'latest_week':str(latest),'latest_week_priorities':counts}))
