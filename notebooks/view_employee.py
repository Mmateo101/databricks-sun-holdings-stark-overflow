# Databricks notebook source
# MAGIC %md
# MAGIC # Saved weekly employee history
# MAGIC Read-only. Reference estimates are assumption dependent; min/max is scenario sensitivity.
# MAGIC Empty selectors choose the first observed employee. No data means unavailable, never zero.

# COMMAND ----------
import sys
from pathlib import Path
from pyspark.sql import functions as F
for name in ('repo_root','catalog','model_schema','expected_owner','model_run_id','employee_id','location_id'):
    dbutils.widgets.text(name,'')
root=Path(dbutils.widgets.get('repo_root'))
if not root.is_absolute():raise ValueError('Set repo_root to the deployed bundle files directory')
sys.path.insert(0,str(root/'src/models'))
from workspace_runtime import Workspace,run_identifier
c=Workspace(spark,dbutils.widgets.get('catalog'),dbutils.widgets.get('model_schema'),dbutils.widgets.get('expected_owner'),require_executor=False)
run=run_identifier(dbutils.widgets.get('model_run_id'))
completion=spark.table(c.table('scenario_model_runs')).where((F.col('model_run_id')==run)&(F.col('status')=='completed')).count()
if completion!=1:raise ValueError('Choose one completed model run')
frame=spark.table(c.table('scenario_week_history')).where(F.col('model_run_id')==run)
for field in ('employee_id','location_id'):
    value=dbutils.widgets.get(field)
    if value:
        if not value.isdigit():raise ValueError('Numeric employee/location identifiers required')
        frame=frame.where(F.col(field)==int(value))
if not dbutils.widgets.get('employee_id'):
    first=frame.select('employee_id','location_id').orderBy('employee_id','location_id').first()
    if first:frame=frame.where((F.col('employee_id')==first.employee_id)&(F.col('location_id')==first.location_id))
display(frame.select('employee_id','location_id','week_start','activity_successes','activity_trials',
 'model_observation_status','reference_prior','reference_probability','sensitivity_min','sensitivity_max').orderBy('week_start'))
