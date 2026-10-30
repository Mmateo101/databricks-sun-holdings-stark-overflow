"""Frozen, probability-sampled review pilot; no heuristic score is an outcome."""
import hashlib
import math
import random
from collections import defaultdict
from statistics import mean, variance

MODEL_RUN = 'synthetic-model-v1'
BATCH_ID = 'synthetic-review-v1'
SEED = 'stark-overflow-review-v1'
OUTCOMES = {'violation', 'no_violation', 'insufficient_evidence'}


def prepare_population(rows, budget=20, per_band=10, *, batch_id=BATCH_ID, model_run_id=MODEL_RUN, seed=SEED):
    """Census both top-k lists; SRS without replacement in three remaining score bands."""
    if type(budget) is not int or budget < 1 or type(per_band) is not int or per_band < 2:
        raise ValueError("Positive review budget and at least two random reviews per band required")
    if any(not isinstance(v,str) or not v or len(v)>100 or any(not(c.isalnum() or c in "-_") for c in v) for v in (batch_id,model_run_id)):
        raise ValueError("Safe batch and model run identifiers required")
    population = []
    seen = set()
    for raw in rows:
        r = dict(raw)
        key = (int(r['employee_id']), int(r['location_id']), str(r['week_start']))
        if key in seen:
            raise ValueError('Duplicate employee-location-week')
        seen.add(key)
        p = float(r['reference_probability'])
        k, n = int(r['activity_successes']), int(r['activity_trials'])
        if not math.isfinite(p) or not 0 <= p <= 1 or not 0 <= k <= n:
            raise ValueError('Invalid score or activity counts')
        if r['model_observation_status'] not in ('assumption_conditioned_activity', 'recorded_scope_zero_positive_actions'):
            raise ValueError('Review cohort requires informed observations')
        r.update(employee_id=key[0], location_id=key[1], week_start=key[2],
                 batch_id=batch_id, model_run_id=model_run_id, reference_probability=p,
                 activity_successes=k, activity_trials=n, baseline_score=k/n if n else 0.0)
        for field in ('actor_positive_checks','actor_positive_applications','full_comp_actor_checks','assigned_checks'):
            if field in r:r[field]=int(r[field])
        for field in ('sensitivity_min','sensitivity_max'):
            if field in r:r[field]=float(r[field])
        if 'week_end' in r:r['week_end']=str(r['week_end'])
        r['case_id'] = hashlib.sha256((model_run_id+'|'+ '|'.join(map(str,key))).encode()).hexdigest()[:20]
        population.append(r)
    if len(population) < max(3, budget):
        raise ValueError('Insufficient cohort for the declared review budget')
    tie = lambda r: (r['employee_id'], r['location_id'], r['week_start'])
    for field, rank in [('reference_probability', 'model_rank'), ('baseline_score', 'baseline_rank')]:
        for i,r in enumerate(sorted(population,key=lambda r:(-r[field],tie(r))),1):
            r[rank]=i
    # Rank bands avoid empty probability bins while retaining known finite populations.
    for i,r in enumerate(sorted(population,key=lambda r:(r['reference_probability'],tie(r)))):
        r['calibration_band'] = min(2,3*i//len(population))
        r['certainty'] = r['model_rank'] <= budget or r['baseline_rank'] <= budget
        r['sampling_stratum'] = ('certainty-' if r['certainty'] else 'sample-')+str(r['calibration_band'])
    strata=defaultdict(list)
    for r in population:
        strata[r['sampling_stratum']].append(r)
    for name,group in sorted(strata.items()):
        group.sort(key=tie)
        count = len(group) if group[0]['certainty'] else min(per_band,len(group))
        selected=set(random.Random(seed+'|'+name).sample(range(len(group)),count))
        for i,r in enumerate(group):
            r.update(selected_for_review=i in selected,stratum_population=len(group),stratum_sample=count,
                     inclusion_probability=count/len(group),review_budget=budget)
    assert len({r['case_id'] for r in population})==len(population)
    return sorted(population,key=lambda r:r['case_id'])


def validate_review(case, review):
    if review.get('outcome') not in OUTCOMES:
        raise ValueError('Choose violation, no_violation or insufficient_evidence')
    if not case['selected_for_review'] or review.get('case_id') != case['case_id']:
        raise ValueError('Outcome does not match a selected case')
    if review.get('label_basis') != 'independent_policy_review':
        raise ValueError('Risk coefficients and model scores are not independent outcomes')
    for field in ('reviewed_by','evidence_reference','review_notes'):
        if not str(review.get(field,'')).strip():
            raise ValueError(field+' is required')
    checked=int(review.get('positive_checks_reviewed',-1))
    expected=int(case['actor_positive_checks'])
    if not 0 <= checked <= expected:
        raise ValueError('Reviewed check count exceeds the frozen actor scope')
    if review['outcome'] != 'insufficient_evidence':
        if not review.get('applicable_policy_confirmed') or not str(review.get('policy_reference','')).strip():
            raise ValueError('Decisive outcomes require confirmed applicable policies')
    if review['outcome']=='violation':
        if checked<1 or not str(review.get('violating_check_id','')).isdigit() or not str(review.get('violating_business_date','')).strip():
            raise ValueError('Violation requires at least one inspected positive check and its ID')
    if review['outcome']=='no_violation':
        if not review.get('full_week_scope_reviewed') or checked!=expected:
            raise ValueError('A negative requires all positive actor checks and complete policy review')
    return dict(review)


def evaluate(population, reviews):
    """Design-based estimates are released only after the planned sample is resolved."""
    if not population or len({(r['batch_id'],r['model_run_id']) for r in population})!=1:
        raise ValueError('One nonempty frozen population is required')
    cases={r['case_id']:r for r in population if r['selected_for_review']}
    groups=defaultdict(list)
    for review in reviews:
        if review.get('case_id') not in cases:
            raise ValueError('Review refers to an unknown or unsampled case')
        validate_review(cases[review['case_id']],review)
        groups[review['case_id']].append(review)
    labels={}
    disputed=[]
    for cid,items in groups.items():
        decisive={r['outcome'] for r in items if r['outcome']!='insufficient_evidence'}
        if len(decisive)>1:
            disputed.append(cid)
        elif decisive:
            labels[cid]=int(next(iter(decisive))=='violation')
    result={'batch_id':population[0]['batch_id'],'model_run_id':population[0]['model_run_id'],'cohort_size':len(population),
            'planned_reviews':len(cases),'cases_with_any_review':len(groups),'decisive_reviews':len(labels),
            'disputed_cases':disputed,'unresolved_reviews':len(cases)-len(labels),
            'target':'at_least_one_recorded_positive_discount_policy_violation_in_employee_location_week',
            'baseline':'positive_discount_check_rate_not_original_risk_coefficient',
            'probability_status':'calibration_not_established','methods':{}}
    for method in ('model','baseline'):
        ranked=sorted(population,key=lambda r:r[method+'_rank'])
        budget=ranked[0]['review_budget']
        top=ranked[:budget]
        positives=sum(labels.get(r['case_id'],0) for r in top)
        resolved=sum(r['case_id'] in labels for r in top)
        result['methods'][method]={'budget':budget,'verified_violations':positives,'resolved_top_cases':resolved,
          'precision_at_budget':positives/budget if resolved==budget else None,
          'precision_identification_bounds':[positives/budget,(positives+budget-resolved)/budget],
          'recall_estimate':None,'recall_se_approx':None,'recall_95_interval_approx':None}
    result.update(weighted_brier=None,weighted_log_loss=None,calibration=[],estimated_violating_weeks=None)
    if len(labels)!=len(cases):
        result['status']='awaiting_independent_reviews'
        return result
    strata=defaultdict(list)
    for r in cases.values():strata[r['sampling_stratum']].append(r)
    degenerate=any(len(rows)<rows[0]['stratum_population'] and len({labels[r['case_id']] for r in rows})==1 for rows in strata.values())
    def estimate(value,band=None):
        total,var_total=0.0,0.0
        for rows in strata.values():
            if band is not None and rows[0]['calibration_band']!=band:continue
            n,N=len(rows),rows[0]['stratum_population']
            if n!=rows[0]['stratum_sample']:
                raise ValueError('Planned stratum sample is incomplete')
            values=[value(r,labels[r['case_id']]) for r in rows]
            total+=N*mean(values)
            if n<N:
                if n<2:raise ValueError('At least two sampled cases required for variance')
                var_total+=N*N*(1-n/N)*variance(values)/n
        return total,var_total
    total,total_var=estimate(lambda r,y:y)
    N=len(population)
    result['estimated_violating_weeks']=total
    result['estimated_violating_weeks_se']=math.sqrt(total_var)
    brier,_=estimate(lambda r,y:(r['reference_probability']-y)**2)
    logloss,_=estimate(lambda r,y:-math.log(max(1e-15,min(1-1e-15,r['reference_probability'])) if y else max(1e-15,1-min(1-1e-15,r['reference_probability']))))
    result.update(status='reviewed_pilot_estimates',weighted_brier=brier/N,weighted_log_loss=logloss/N)
    for method,data in result['methods'].items():
        numerator=data['verified_violations']
        if total>0:
            recall=numerator/total
            se=numerator*math.sqrt(total_var)/(total*total)
            data.update(recall_estimate=recall,recall_se_approx=se,
                        recall_95_interval_approx=None if degenerate else [max(0,recall-1.96*se),min(1,recall+1.96*se)])
    for band in range(3):
        cohort=[r for r in population if r['calibration_band']==band]
        positives,var_total=estimate(lambda r,y:y,band)
        observed=positives/len(cohort)
        se=math.sqrt(var_total)/len(cohort)
        result['calibration'].append({'band':band,'cohort_size':len(cohort),
          'reviewed_cases':sum(r['calibration_band']==band for r in cases.values()),
          'mean_predicted':mean(r['reference_probability'] for r in cohort),
          'estimated_observed_rate':observed,'observed_rate_se':se,
          'observed_rate_95_interval_approx':None if degenerate else [max(0,observed-1.96*se),min(1,observed+1.96*se)]})
    result['uncertainty_method']='stratified SRS finite-population variance; recall delta method; normal 95% approximation, potentially unstable in a small pilot'
    result['probability_status']='calibration_assessed_on_pilot_not_recalibrated'
    if degenerate:result['interval_warning']='An entire sampled stratum has one outcome class; normal intervals are withheld because plug-in variance can understate uncertainty.'
    return result
