# Databricks notebook source
# MAGIC %md
# MAGIC # Employee time series
# MAGIC Each employee against their own history, after removing what their store did (same week, daypart and channel).
# MAGIC Labels every period rising, falling, spike, stable or insufficient_history. Thresholds are set by alarm rate,
# MAGIC not by reviewed outcomes. Method: docs/time-series.md.

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
import time_series
c=Workspace(spark,dbutils.widgets.get('catalog'),dbutils.widgets.get('model_schema'),dbutils.widgets.get('expected_owner'))
run=run_identifier(dbutils.widgets.get('model_run_id'))
gold=identifier(dbutils.widgets.get('gold_namespace'),2)
config=json.loads((root/'src/models/time_series.json').read_text(encoding='utf-8'))
code_hash=fingerprint([(n,(root/'src/models'/n).read_text(encoding='utf-8')) for n in ('time_series.py','score_time_series.py')]+[('config',config),('gold',gold)])
c.ensure_schema()
if spark.catalog.tableExists(c.table('ts_model_runs')):
    old=spark.table(c.table('ts_model_runs')).where(F.col('model_run_id')==run).collect()
    if len(old)==1:
        if old[0].code_sha256!=code_hash:raise ValueError('Completed time series identity changed; use a new run ID')
        dbutils.notebook.exit(json.dumps({'status':'already_completed','model_run_id':run}))
    if old:raise ValueError('Ambiguous time series completion')

# COMMAND ----------
# Checks with their owner (first payment taker, gift card sales excluded), fraud week and daypart x channel cell
inds=list(config['indicators'])
spark.sql(f"""
CREATE OR REPLACE TEMP VIEW ts_checks AS
WITH own AS (
  SELECT location_id, business_date, check_id, min_by(employee_id, payment_ordinal) AS employee_id
  FROM {gold}.silver_payments WHERE generation_id = '{run}' AND payment_type <> 'GC Sold' GROUP BY ALL),
v AS (SELECT location_id, business_date, check_id, count(*) AS void_items
      FROM {gold}.silver_voids WHERE generation_id = '{run}' GROUP BY ALL),
chk AS (
  SELECT c.location_id, c.business_date, c.check_id, hour(c.open_time) AS h, rc.revenue_center_name AS rc
  FROM {gold}.silver_checks c LEFT JOIN {gold}.silver_revenue_centers rc
    ON rc.revenue_center_id = c.revenue_center_id AND rc.generation_id = '{run}'
  WHERE c.generation_id = '{run}')
SELECT o.employee_id, f.location_id,
  date_sub(f.business_date, (dayofweek(f.business_date) + 2) % 7) AS week_start,
  CASE WHEN k.h BETWEEN 11 AND 13 THEN 'Lunch' WHEN k.h BETWEEN 14 AND 16 THEN 'Afternoon'
       WHEN k.h BETWEEN 17 AND 20 THEN 'Dinner' WHEN k.h >= 21 OR k.h <= 2 THEN 'Late' ELSE 'Other' END || '|' ||
  CASE WHEN k.rc = 'In-Store' THEN 'Dine-in'
       WHEN k.rc IN ('To Go', 'Online', 'Online AS', 'Catering') OR k.rc LIKE 'Olo%' THEN 'Off-premise'
       ELSE 'Delivery partner' END AS cell,
  CAST(coalesce(f.has_positive_discount, false) AS INT) AS discount_frequency,
  CAST(coalesce(f.gross_sales > 0 AND f.recorded_discount_amount >= f.gross_sales, false) AS INT) AS full_comp,
  CAST(coalesce(f.has_positive_discount, false) AND coalesce(v.void_items, 0) > 0 AS INT) AS discount_void,
  coalesce(v.void_items, 0) AS voids
FROM {gold}.gold_check_facts f
JOIN own o USING (location_id, business_date, check_id)
JOIN chk k USING (location_id, business_date, check_id)
LEFT JOIN v USING (location_id, business_date, check_id)
WHERE f.generation_id = '{run}' AND o.employee_id IS NOT NULL AND o.employee_id <> 0
""")
m=config['min_cell_checks']
sums=lambda p:', '.join(f'sum({i}) AS {p}{i}' for i in inds)
loo_sw={i:f'CASE WHEN s.sn - e.en >= {m} THEN (s.s_{i} - e.e_{i}) / (s.sn - e.en) ELSE t.t_{i} / t.tn END' for i in inds}
loo={i:f'CASE WHEN c.cn - x.n >= {m} THEN (c.c_{i} - x.k_{i}) / (c.cn - x.n) ELSE {loo_sw[i]} END' for i in inds}
frame=spark.sql(f"""
WITH x AS (SELECT employee_id, location_id, week_start, cell, count(*) AS n, {sums('k_')} FROM ts_checks GROUP BY ALL),
c AS (SELECT location_id, week_start, cell, count(*) AS cn, {sums('c_')} FROM ts_checks GROUP BY ALL),
s AS (SELECT location_id, week_start, count(*) AS sn, {sums('s_')} FROM ts_checks GROUP BY ALL),
e AS (SELECT employee_id, location_id, week_start, count(*) AS en, {sums('e_')} FROM ts_checks GROUP BY ALL),
t AS (SELECT location_id, count(*) AS tn, {sums('t_')} FROM ts_checks GROUP BY ALL)
SELECT x.employee_id, max_by(x.location_id, x.n) AS location_id, x.week_start, CAST(sum(x.n) AS DOUBLE) AS n,
  {', '.join(f'CAST(sum(x.k_{i}) AS DOUBLE) AS k_{i}' for i in inds)},
  {', '.join(f'sum(x.n * ({loo[i]})) AS e_{i}' for i in inds)}
FROM x
JOIN c ON c.location_id = x.location_id AND c.week_start = x.week_start AND c.cell = x.cell
JOIN s ON s.location_id = x.location_id AND s.week_start = x.week_start
JOIN e ON e.employee_id = x.employee_id AND e.location_id = x.location_id AND e.week_start = x.week_start
JOIN t ON t.location_id = x.location_id
GROUP BY x.employee_id, x.week_start
""").toPandas()
if frame.empty:raise ValueError('No owned checks for the time series')

# COMMAND ----------
long,short,facts=time_series.run(frame,config)
for name,data in [('ts_employee_period',long),('ts_employee_week',short)]:
    sdf=spark.createDataFrame(data).withColumn('model_run_id',F.lit(run))
    c.append(name,sdf,run)
    if spark.table(c.table(name)).where(F.col('model_run_id')==run).count()!=len(data):raise ValueError('Time series persistence mismatch: '+name)
manifest=dict(model_run_id=run,status='completed',code_sha256=code_hash,model_version=config['model_version'],
              employee_weeks=len(frame),thresholds_json=json.dumps(facts['thresholds'],sort_keys=True),
              params_json=json.dumps(facts['params'],sort_keys=True),rising_rate=facts['rising_rate'],
              evaluable_periods=facts['evaluable_periods'])
c.append('ts_model_runs',spark.createDataFrame([manifest]).withColumn('completed_at',F.current_timestamp()),run)
dbutils.notebook.exit(json.dumps({'status':'completed','model_run_id':run,'employee_weeks':len(frame),
  'thresholds':facts['thresholds'],'rising_rate':round(facts['rising_rate'],4),'evaluable_periods':facts['evaluable_periods'],
  'employees_by_period_weeks':facts['employees'],'calibration':'alarm_rate_not_reviewed_outcomes'}))
