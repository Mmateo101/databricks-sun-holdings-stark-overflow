# Databricks notebook source
# MAGIC %md
# MAGIC # Count-aware temporal policy-review model
# MAGIC Fitted unlabeled background; declared class and temporal assumptions.
# MAGIC Grid extrema are sensitivity, not credible intervals. No fraud accuracy is claimed.

# COMMAND ----------
import json,sys
from pathlib import Path
from pyspark.sql import functions as F,types as T
for name in ('repo_root','catalog','model_schema','expected_owner','model_run_id','actor_run_id'):
    dbutils.widgets.text(name,'')
root=Path(dbutils.widgets.get('repo_root'))
if not root.is_absolute():raise ValueError('Absolute deployed repo_root required')
sys.path.insert(0,str(root/'src/models'))
from workspace_runtime import Workspace,run_identifier,fingerprint
from weekly_scenarios import scenario_grid,training_boundary,observation_status,fit_background,filter_history,binomial_log_pmf
from count_model import beta_binomial_log_pmf
c=Workspace(spark,dbutils.widgets.get('catalog'),dbutils.widgets.get('model_schema'),dbutils.widgets.get('expected_owner'))
run=run_identifier(dbutils.widgets.get('model_run_id'));actor_run=run_identifier(dbutils.widgets.get('actor_run_id'))
config=json.loads((root/'src/models/weekly_scenarios.json').read_text(encoding='utf-8'))
code_hash=fingerprint([(name,(root/'src/models'/name).read_text(encoding='utf-8')) for name in ('weekly_scenarios.py','count_model.py','inference.py')]+[('config',config)])
c.ensure_schema()
if spark.catalog.tableExists(c.table('scenario_model_runs')):
    old=spark.table(c.table('scenario_model_runs')).where(F.col('model_run_id')==run).collect()
    if len(old)==1:
        if old[0].code_sha256!=code_hash or old[0].actor_run_id!=actor_run:raise ValueError('Completed model identity changed; use a new run ID')
        dbutils.notebook.exit(json.dumps({'status':'already_completed','model_run_id':run}))
    if old:raise ValueError('Ambiguous scenario completion')
completion=spark.table(c.table('actor_model_runs')).where((F.col('model_run_id')==actor_run)&(F.col('status')=='completed')).collect()
if len(completion)!=1:raise ValueError('Exactly one completed actor run required')
scenarios=scenario_grid(config)
source_ref,snapshot=c.frozen_source(c.table('actor_week_history'))
if spark.catalog.tableExists(c.table('scenario_run_inputs')):
    old=spark.table(c.table('scenario_run_inputs')).where(F.col('model_run_id')==run).collect()
    if old:
        if len(old)!=1 or old[0].code_sha256!=code_hash or old[0].parameters_json!=json.dumps(config,sort_keys=True):raise ValueError('Retry code or parameters changed')
        snapshot=json.loads(old[0].snapshot_json)
        source_ref=f"{snapshot['table']} VERSION AS OF {int(snapshot['version'])}"
frame=spark.sql(f'SELECT * FROM {source_ref}').where(F.col('model_run_id')==actor_run)
rows=[r.asDict() for r in frame.collect()]
if len(rows)!=completion[0].weekly_rows:raise ValueError('Frozen actor input size mismatch')
c.append('scenario_run_inputs',spark.createDataFrame([dict(model_run_id=run,actor_run_id=actor_run,code_sha256=code_hash,
  parameters_json=json.dumps(config,sort_keys=True),snapshot_json=json.dumps(snapshot,sort_keys=True))]),run)
training_weeks,cutoff=training_boundary(rows,config['training_full_weeks'])
training=[r for r in rows if r['week_start'] in training_weeks and observation_status(r) in ('assumption_conditioned_activity','recorded_scope_zero_positive_actions')]
pooled=fit_background(training,config['fit']);baselines={None:pooled};fits=[]
for location in [None]+sorted({r['location_id'] for r in rows}):
    subset=[r for r in training if r['location_id']==location] if location is not None else training
    try:fit=fit_background(subset,config['fit']) if location is not None else pooled
    except ValueError:fit={**pooled,'fit_status':'pooled_fallback'}
    baselines[location]=fit
    fits.append(dict(location_id=location,**fit,local_training_rows=len(subset),scoring_start=str(cutoff)))
scored=filter_history(rows,scenarios,baselines,cutoff)
extra={'model_observation_status':T.StringType(),'reference_probability':T.DoubleType(),'reference_prior':T.DoubleType(),
 'sensitivity_min':T.DoubleType(),'sensitivity_max':T.DoubleType(),'sensitivity_median':T.DoubleType(),'sensitivity_variance':T.DoubleType(),
 'scenario_probabilities':T.ArrayType(T.DoubleType()),'scenario_priors':T.ArrayType(T.DoubleType()),'scenario_log_ratios':T.ArrayType(T.DoubleType()),
 'elapsed_model_weeks':T.LongType(),'baseline_mean':T.DoubleType(),'baseline_kappa':T.DoubleType()}
schema=T.StructType(frame.schema.fields+[T.StructField(k,v) for k,v in extra.items()])
scores=spark.createDataFrame(scored,schema).withColumnRenamed('model_run_id','actor_run_id').withColumn('model_run_id',F.lit(run))
if scores.count()!=len(rows) or scores.select('employee_id','location_id','week_start').distinct().count()!=len(rows):raise ValueError('Scenario output grain mismatch')
predictive=[]
for r in scored:
    if r['model_observation_status'] not in ('assumption_conditioned_activity','recorded_scope_zero_positive_actions'):continue
    fit=baselines[r['location_id']];k,n=int(r['activity_successes']),int(r['activity_trials'])
    predictive.append((beta_binomial_log_pmf(k,n,fit['mean']*fit['kappa'],(1-fit['mean'])*fit['kappa']),binomial_log_pmf(k,n,fit['binomial_mean'])))
if not predictive:raise ValueError('No informed held-out observations')
diagnostic=dict(heldout_rows=len(predictive),bb_mean_log_score=sum(x[0] for x in predictive)/len(predictive),
 binomial_mean_log_score=sum(x[1] for x in predictive)/len(predictive),interpretation='count_prediction_not_violation_detection')
for name,data in [('scenario_baselines',spark.createDataFrame(fits)),('scenario_parameters',spark.createDataFrame(scenarios)),
 ('scenario_week_history',scores),('scenario_diagnostics',spark.createDataFrame([diagnostic]))]:
    data=data.withColumn('model_run_id',F.lit(run)).withColumn('parameter_status',F.lit('assumption_sensitivity_only'))
    c.append(name,data,run)
    if spark.table(c.table(name)).where(F.col('model_run_id')==run).count()!=data.count():raise ValueError('Scenario persistence mismatch: '+name)
manifest=spark.createDataFrame([dict(model_run_id=run,actor_run_id=actor_run,status='completed',weekly_rows=len(rows),scenario_count=len(scenarios),code_sha256=code_hash)]).withColumn('completed_at',F.current_timestamp())
c.append('scenario_model_runs',manifest,run)
dbutils.notebook.exit(json.dumps({'status':'completed','model_run_id':run,'weekly_rows':len(rows),'scenarios':len(scenarios),'diagnostic':diagnostic,'calibration':'not_established'}))
