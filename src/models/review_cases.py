# Databricks notebook source
# MAGIC %md
# MAGIC # Independent policy review pilot
# MAGIC Managers or teammates with confirmed policies and approval evidence review
# MAGIC the recorded discount actor's employee-location-week. Intent is not required.
# MAGIC Scores and selection reasons are hidden in the reviewer display.
# MAGIC A risk coefficient, unusual activity, or a candidate-policy screen is not a verified outcome.
# MAGIC Choose `inspect` to view the queue and check evidence; `submit_review` saves an audited outcome.
# MAGIC Choose `evaluate` to recalculate metrics. Unknown or disputed cases remain unresolved.

# COMMAND ----------
import hashlib
import html
import json
from datetime import datetime,timezone
from pathlib import Path
import sys
from pyspark.sql import functions as F,types as T

for name in ('repo_root','catalog','model_schema','expected_owner','model_run_id','review_batch_id','week_start'):
    dbutils.widgets.text(name,'')
dbutils.widgets.dropdown('action','inspect',['inspect','prepare','submit_review','evaluate'])
dbutils.widgets.text('case_id','')
dbutils.widgets.dropdown('outcome','insufficient_evidence',['insufficient_evidence','violation','no_violation'])
for name in ('policy_reference','evidence_reference','review_notes','positive_checks_reviewed','violating_check_id','violating_business_date'):
    dbutils.widgets.text(name,'')
for name in ('applicable_policy_confirmed','full_week_scope_reviewed'):
    dbutils.widgets.dropdown(name,'false',['false','true'])
root=Path(dbutils.widgets.get('repo_root'))
if not root.is_absolute():raise ValueError('repo_root must be absolute')
sys.path.insert(0,str(root/'src/models'))
from review_pilot import prepare_population,validate_review,evaluate
from workspace_runtime import Workspace,run_identifier,identifier,MARKER
MODEL_RUN=run_identifier(dbutils.widgets.get('model_run_id'))
BATCH_ID=run_identifier(dbutils.widgets.get('review_batch_id'))
action=dbutils.widgets.get('action')
c=Workspace(spark,dbutils.widgets.get('catalog'),dbutils.widgets.get('model_schema'),dbutils.widgets.get('expected_owner'),require_executor=action=='prepare')
SCHEMA=c.namespace
OWNER=c.owner
principal=c.executor
OUTPUTS={'review_pilot_manifest','review_pilot_population','review_pilot_outcomes','review_pilot_evaluations','review_pilot_evidence'}
config={'batch_id':BATCH_ID,'model_run_id':MODEL_RUN,'review_budget':20,'random_reviews_per_band':10}

def table(name):return f'{SCHEMA}.{name}'
def ensure(name,ddl):
    if name not in OUTPUTS:raise ValueError('Unknown review output')
    c.ensure_table(name,ddl=ddl)
def append(name,frame,key):c.append(name,frame,key)

if action=='prepare':
    if principal!=OWNER:raise ValueError('Only the owner prepares a frozen review batch')
    source_ref,snapshot=c.frozen_source(table('scenario_week_history'))
    if spark.catalog.tableExists(table('review_pilot_manifest')):
        previous=spark.table(table('review_pilot_manifest')).where(F.col('batch_id')==BATCH_ID).collect()
        if previous:
            if len(previous)!=1:raise ValueError('Ambiguous review manifest')
            prior_config=json.loads(previous[0].config_json)
            if prior_config['model_run_id']!=MODEL_RUN:raise ValueError('Batch already belongs to another model run')
            snapshot=prior_config['model_snapshot']
            source_ref=f"{snapshot['table']} VERSION AS OF {int(snapshot['version'])}"
    frame=spark.sql(f'SELECT * FROM {source_ref}').where((F.col('model_run_id')==MODEL_RUN)&F.col('model_observation_status').isin('assumption_conditioned_activity','recorded_scope_zero_positive_actions'))
    from datetime import date
    requested=dbutils.widgets.get('week_start').strip()
    week=date.fromisoformat(requested) if requested else frame.agg(F.max('week_start')).first()[0]
    if week is None:raise ValueError('No informed review week')
    config.update(week_start=str(week),model_snapshot=snapshot)
    fields=['employee_id','location_id','week_start','week_end','model_observation_status','reference_probability',
      'sensitivity_min','sensitivity_max','activity_successes','activity_trials','actor_positive_checks',
      'actor_positive_applications','actor_positive_amount','full_comp_actor_checks','assigned_checks']
    rows=[r.asDict() for r in frame.where(F.col('week_start')==week).select(*fields)
      .withColumn('actor_positive_amount',F.col('actor_positive_amount').cast('string')).collect()]
    population=prepare_population(rows,config['review_budget'],config['random_reviews_per_band'],batch_id=BATCH_ID,model_run_id=MODEL_RUN)
    encoded=json.dumps(population,sort_keys=True,default=str,separators=(',',':'))
    fingerprint=hashlib.sha256(encoded.encode()).hexdigest()
    config_json=json.dumps(config,sort_keys=True)
    ensure('review_pilot_manifest','batch_id STRING, model_run_id STRING, population_sha256 STRING, config_json STRING, population_count BIGINT, selected_count BIGINT, prepared_at TIMESTAMP')
    existing=spark.table(table('review_pilot_manifest')).where(F.col('batch_id')==BATCH_ID).collect()
    if existing and (len(existing)!=1 or existing[0].population_sha256!=fingerprint or existing[0].config_json!=config_json):
        raise ValueError('Frozen batch changed; create a separately approved batch instead')
    frame=spark.createDataFrame(population)
    ensure('review_pilot_population',', '.join(f'`{f.name}` {f.dataType.simpleString()}' for f in frame.schema.fields))
    ensure('review_pilot_outcomes','batch_id STRING,case_id STRING,review_id STRING,reviewed_by STRING,reviewed_at TIMESTAMP,outcome STRING,label_basis STRING,policy_reference STRING,evidence_reference STRING,review_notes STRING,applicable_policy_confirmed BOOLEAN,positive_checks_reviewed BIGINT,full_week_scope_reviewed BOOLEAN,violating_check_id STRING,violating_business_date STRING')
    ensure('review_pilot_evaluations','batch_id STRING,evaluation_id STRING,evaluated_by STRING,evaluated_at TIMESTAMP,outcomes_version BIGINT,result_json STRING')
    append('review_pilot_population',frame,BATCH_ID)
    saved=spark.table(table('review_pilot_population')).where(F.col('batch_id')==BATCH_ID)
    if saved.count()!=len(population) or saved.select('case_id').distinct().count()!=len(population):
        raise ValueError('Review population persistence mismatch')
    scenario=spark.table(table('scenario_model_runs')).where((F.col('model_run_id')==MODEL_RUN)&(F.col('status')=='completed')).collect()
    if len(scenario)!=1:raise ValueError('Exactly one completed model run required')
    actor=spark.table(table('actor_run_inputs')).where(F.col('model_run_id')==scenario[0].actor_run_id).collect()
    if len(actor)!=1:raise ValueError('Missing actor provenance')
    refs=json.loads(actor[0].source_versions_json)
    event_ref=identifier(refs['events']['table'],3)+f" VERSION AS OF {int(refs['events']['version'])}"
    fact_ref=identifier(refs['facts']['table'],3)+f" VERSION AS OF {int(refs['facts']['version'])}"
    evidence=spark.sql(f"""SELECT p.batch_id,p.case_id,e.business_date,e.check_id,
      count(*) AS positive_applications,sum(CAST(e.amount AS DECIMAL(38,6))) AS actor_positive_amount,
      max(f.gross_sales) AS check_gross_sales,max(f.recorded_discount_amount) AS check_discount_amount,
      to_json(collect_list(named_struct('discount_id',e.discount_id,'discount_name',e.discount_name,
       'scope',e.discount_level,'item_sequence',e.item_sequence,'ordinal',e.discount_ordinal,
       'amount',e.amount,'recorded_manager_id',e.manager_id))) AS applications_json
      FROM {table('review_pilot_population')} p
      JOIN {event_ref} e
       ON p.employee_id=e.discount_employee_id AND p.location_id=e.location_id
       AND e.business_date BETWEEN CAST(p.week_start AS DATE) AND CAST(p.week_end AS DATE)
      JOIN {fact_ref} f
       ON e.location_id=f.location_id AND e.business_date=f.business_date AND e.check_id=f.check_id
      WHERE p.batch_id='{BATCH_ID}' AND p.selected_for_review AND e.amount>0
      GROUP BY p.batch_id,p.case_id,e.business_date,e.check_id""")
    ensure('review_pilot_evidence',', '.join(f'`{f.name}` {f.dataType.simpleString()}' for f in evidence.schema.fields))
    append('review_pilot_evidence',evidence,BATCH_ID)
    evidence_saved=spark.table(table('review_pilot_evidence')).where(F.col('batch_id')==BATCH_ID)
    counts=evidence_saved.groupBy('case_id').agg(F.count('*').alias('packet_checks'),F.sum('positive_applications').alias('packet_applications'))
    mismatch=(saved.where('selected_for_review').join(counts,'case_id','left')
      .where((F.coalesce(F.col('packet_checks'),F.lit(0))!=F.col('actor_positive_checks'))|
             (F.coalesce(F.col('packet_applications'),F.lit(0))!=F.col('actor_positive_applications'))).count())
    if mismatch:raise ValueError('Evidence packets do not cover every sampled positive actor check/application')
    manifest=spark.createDataFrame([dict(batch_id=BATCH_ID,model_run_id=MODEL_RUN,population_sha256=fingerprint,
       config_json=config_json,population_count=len(population),selected_count=sum(r['selected_for_review'] for r in population),prepared_at=datetime.now(timezone.utc))])
    append('review_pilot_manifest',manifest,BATCH_ID)

if not spark.catalog.tableExists(table('review_pilot_manifest')):raise ValueError('Owner must prepare the pilot first')
manifest=spark.table(table('review_pilot_manifest')).where(F.col('batch_id')==BATCH_ID).collect()
if len(manifest)!=1:raise ValueError('Review batch has no unique completed manifest')
for name in OUTPUTS:
    meta=spark.sql(f"SELECT table_owner,comment FROM {c.catalog}.information_schema.tables WHERE table_schema='{c.schema}' AND table_name='{name}'").first()
    if not meta or meta.table_owner!=OWNER or meta.comment!=MARKER:raise ValueError('Unrecognized review output')
population=[r.asDict() for r in spark.table(table('review_pilot_population')).where(F.col('batch_id')==BATCH_ID).collect()]
selected=[r for r in population if r['selected_for_review']]
case_id=dbutils.widgets.get('case_id').strip()
case=next((r for r in selected if r['case_id']==case_id),None)
if case_id and case is None:raise ValueError('Unknown selected case ID')
packet=[]
if case is not None:
    packet=[r.asDict(recursive=True) for r in spark.table(table('review_pilot_evidence'))
      .where((F.col('batch_id')==BATCH_ID)&(F.col('case_id')==case_id)).orderBy('business_date','check_id').collect()]
    for entry in packet:entry['applications']=json.loads(entry.pop('applications_json'))
    if len(packet)!=int(case['actor_positive_checks']):raise ValueError('Evidence packet does not cover all frozen positive actor checks')

if action=='submit_review':
    if case is None:raise ValueError('Choose a case ID before submitting')
    review={name:dbutils.widgets.get(name).strip() for name in ('outcome','policy_reference','evidence_reference','review_notes','positive_checks_reviewed','violating_check_id','violating_business_date')}
    review['positive_checks_reviewed']=int(review['positive_checks_reviewed'])
    review.update(case_id=case_id,reviewed_by=principal,label_basis='independent_policy_review',
      applicable_policy_confirmed=dbutils.widgets.get('applicable_policy_confirmed')=='true',
      full_week_scope_reviewed=dbutils.widgets.get('full_week_scope_reviewed')=='true')
    validate_review(case,review)
    if review['outcome']=='violation' and not any(str(r['check_id'])==review['violating_check_id'] and str(r['business_date'])==review['violating_business_date'] for r in packet):
        raise ValueError('The alleged violating positive check is outside this employee-location-week')
    review.update(batch_id=BATCH_ID,review_id=hashlib.sha256(json.dumps(review,sort_keys=True).encode()).hexdigest(),reviewed_at=datetime.now(timezone.utc))
    review_schema=spark.table(table('review_pilot_outcomes')).schema
    append('review_pilot_outcomes',spark.createDataFrame([review],review_schema),review['review_id'])

if action=='inspect':
    blind=spark.table(table('review_pilot_population')).where((F.col('batch_id')==BATCH_ID)&F.col('selected_for_review'))
    display(blind.select('case_id','employee_id','location_id','week_start','week_end','actor_positive_checks','actor_positive_applications','actor_positive_amount').orderBy('case_id'))
    if packet:
        displayHTML('<pre>'+html.escape(json.dumps(packet,indent=2,default=str))+'</pre>')
    elif case is not None:
        displayHTML('<p>No positive actor discount checks in the frozen recorded scope. Confirm source coverage and applicable policies before submitting an outcome.</p>')
    result={'status':'review_queue_ready','batch_id':BATCH_ID,'cohort':len(population),'selected':len(selected),'case_id':case_id,'packet_checks':len(packet)}
else:
    outcomes_version=int(spark.sql(f'DESCRIBE HISTORY {table("review_pilot_outcomes")} LIMIT 1').first().version)
    reviews=[r.asDict() for r in spark.sql(f'SELECT * FROM {table("review_pilot_outcomes")} VERSION AS OF {outcomes_version}').where(F.col('batch_id')==BATCH_ID).collect()]
    result=evaluate(population,reviews)
    result.update(outcomes_version=outcomes_version,population_sha256=manifest[0].population_sha256)
    result_json=json.dumps(result,sort_keys=True)
    evaluation_id=hashlib.sha256(result_json.encode()).hexdigest()
    frame=spark.createDataFrame([dict(batch_id=BATCH_ID,evaluation_id=evaluation_id,evaluated_by=principal,
      evaluated_at=datetime.now(timezone.utc),outcomes_version=outcomes_version,result_json=result_json)])
    append('review_pilot_evaluations',frame,evaluation_id)
    displayHTML('<pre>'+html.escape(json.dumps(result,indent=2))+'</pre>')
print(json.dumps(result,default=str))
dbutils.notebook.exit(json.dumps(result,default=str))
