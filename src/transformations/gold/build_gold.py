# Databricks notebook source
# MAGIC %md
# MAGIC # Isolated Gold snapshot from accepted Silver
# MAGIC Each Job run owns a new schema. Existing shared tables are never replaced.
# MAGIC Run after the Silver pipeline completes and keep its inputs quiescent during the copy.

# COMMAND ----------
import json,sys,hashlib
from pathlib import Path
from pyspark.sql import functions as F
for name in ('repo_root','catalog','source_catalog','silver_schema','gold_schema','expected_owner','model_run_id'):
    dbutils.widgets.text(name,'')
root=Path(dbutils.widgets.get('repo_root'))
if not root.is_absolute():raise ValueError('Absolute deployed repo_root required')
sys.path.insert(0,str(root/'src/models'))
from workspace_runtime import Workspace,identifier,run_identifier,fingerprint
run=run_identifier(dbutils.widgets.get('model_run_id'))
source=identifier(dbutils.widgets.get('source_catalog'))+'.'+identifier(dbutils.widgets.get('silver_schema'))
suffix=hashlib.sha256(run.encode()).hexdigest()[:12]
schema=identifier(dbutils.widgets.get('gold_schema'))+'_'+suffix
c=Workspace(spark,dbutils.widgets.get('catalog'),schema,dbutils.widgets.get('expected_owner'))
c.ensure_schema()
code_hash=fingerprint([(p.name,p.read_text(encoding='utf-8')) for p in [root/'src/transformations/gold'/n for n in ('check_facts.sql','discount_events.sql','location_day.sql')]]+[('source',source)])
if spark.catalog.tableExists(c.table('gold_run_inputs')):
    previous=spark.table(c.table('gold_run_inputs')).where(F.col('model_run_id')==run).collect()
    if previous and (len(previous)!=1 or previous[0].code_sha256!=code_hash):raise ValueError('Gold retry source or SQL changed')
c.append('gold_run_inputs',spark.createDataFrame([dict(model_run_id=run,source_namespace=source,code_sha256=code_hash)]),run)
names=['silver_checks','silver_check_items','silver_discount_events','silver_payments','silver_employees','silver_items','silver_locations','silver_revenue_centers']
for name in names:
    # Silver materialized views cannot always be time-travelled. Persist their
    # inputs once in this isolated run; downstream actor/model reads pin Delta versions.
    frame=spark.table(source+'.'+name).withColumn('generation_id',F.lit(run))
    c.append(name,frame,run)
    if spark.table(c.table(name)).count()!=frame.count():raise ValueError('Snapshot count changed during copy/retry: '+name)
replacements={'{{source_schema}}':c.namespace,'{{storage_schema}}':c.namespace,'{{generation_id_literal}}':"'"+run+"'"}
for filename,name in [('check_facts.sql','gold_check_facts'),('discount_events.sql','gold_discount_events'),('location_day.sql','gold_location_day')]:
    sql=(root/'src/transformations/gold'/filename).read_text(encoding='utf-8')
    for key,value in replacements.items():sql=sql.replace(key,value)
    if '{{' in sql:raise ValueError('Unresolved Gold template')
    c.append(name,spark.sql(sql),run)
checks=spark.table(c.table('gold_check_facts'))
if not checks.count():raise ValueError('No accepted checks for Gold publication')
if checks.count()!=checks.select('location_id','business_date','check_id').distinct().count():raise ValueError('Gold check grain mismatch')
if checks.count()!=spark.table(c.table('silver_checks')).count():raise ValueError('Gold lost accepted checks')
events=spark.table(c.table('gold_discount_events'))
if events.count()!=spark.table(c.table('silver_discount_events')).count():raise ValueError('Gold lost discount occurrences')
c.append('gold_publication',spark.createDataFrame([dict(slot=1,generation_id=run)]),run)
for key,value in {'gold_namespace':c.namespace,'facts_table':c.table('gold_check_facts'),
 'events_table':c.table('gold_discount_events'),'payments_table':c.table('silver_payments')}.items():
    dbutils.jobs.taskValues.set(key=key,value=value)
dbutils.notebook.exit(json.dumps({'status':'completed','namespace':c.namespace,'generation_id':run}))
