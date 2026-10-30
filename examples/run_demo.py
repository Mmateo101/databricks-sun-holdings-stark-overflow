"""Generate a public, synthetic dashboard using the actual temporal model."""
from collections import defaultdict
from datetime import date,timedelta
import json
import math
from pathlib import Path
import random
import sys
ROOT=Path(__file__).resolve().parents[1]
sys.path.insert(0,str(ROOT/'src/models'))
from weekly_scenarios import scenario_grid,training_boundary,fit_background,filter_history,observation_status,binomial_log_pmf
from count_model import beta_binomial_log_pmf

def synthetic_rows():
    rng=random.Random('stark-overflow-public-demo-v1')
    rows=[]
    for employee in range(1,31):
        for week in range(16 if employee!=30 else 4):
            if employee==5 and week==8:continue
            n=rng.randint(45,90);rate=.08+rng.uniform(-.035,.035)
            if employee==2 and week>=6:rate=.43
            if employee==3 and 5<=week<=7:rate=.48
            k=max(1,min(n,round(n*rate)))
            if employee==4 and week==9:k=0
            rows.append(dict(employee_id=employee,location_id=(employee-1)%3+1,
              week_start=date(2026,1,1)+timedelta(weeks=week),week_end=date(2026,1,7)+timedelta(weeks=week),
              activity_successes=k,activity_trials=n,actor_positive_checks=k,actor_positive_applications=k,
              actor_positive_amount=str(k*7.5),full_comp_actor_checks=int(k>20),assigned_checks=n,
              is_partial_week=False,location_source_days=7,action_only_checks=0,multi_actor_checks=0,
              unknown_actor_checks=0,incomplete_discount_checks=int(employee==1 and week==10)))
    return rows

def build_payload():
    config=json.loads((ROOT/'config/weekly-scenarios.json').read_text(encoding='utf-8'))
    scenarios=scenario_grid(config);rows=synthetic_rows()
    training_weeks,cutoff=training_boundary(rows,config['training_full_weeks'])
    train=[r for r in rows if r['week_start'] in training_weeks and not observation_status(r).startswith('prior_only')]
    pooled=fit_background(train,config['fit']);baselines={None:pooled}
    for location in (1,2,3):
        baselines[location]=fit_background([r for r in train if r['location_id']==location],config['fit'])
    scored=filter_history(rows,scenarios,baselines,cutoff)
    employees=defaultdict(list);means=defaultdict(list);pred=[]
    codes={'background_training_period':0,'assumption_conditioned_activity':1,'recorded_scope_zero_positive_actions':2}
    for r in scored:
        w=(r['week_start']-date(2026,1,1)).days//7
        status=codes.get(r['model_observation_status'],3)
        roundp=lambda key:None if r[key] is None else round(r[key],8)
        employees[(r['employee_id'],r['location_id'])].append([w,r['activity_successes'],r['activity_trials'],
          roundp('reference_probability'),roundp('sensitivity_min'),roundp('sensitivity_max'),roundp('reference_prior'),
          status,float(r['actor_positive_amount']),r['full_comp_actor_checks'],r['actor_positive_checks']])
        if status in (1,2):
            for i,p in enumerate(r['scenario_probabilities']):means[(i,w)].append(p)
            fit=baselines[r['location_id']];k,n=r['activity_successes'],r['activity_trials']
            pred.append((beta_binomial_log_pmf(k,n,fit['mean']*fit['kappa'],(1-fit['mean'])*fit['kappa']),binomial_log_pmf(k,n,fit['binomial_mean'])))
    return {'data_kind':'synthetic','seed':'stark-overflow-public-demo-v1',
      'employees':[[e,l,h] for (e,l),h in sorted(employees.items())],
      'grid':[[s['scenario_index'],s['weekly_base_rate'],s['memory_half_life_weeks'],s['activity_odds_multiplier'],s['concentration_multiplier']] for s in scenarios],
      'scenarios':[[w,i,round(sum(p)/len(p),8),len(p)] for (i,w),p in sorted(means.items())],
      'diagnostic':{'heldout_rows':len(pred),'bb_mean_log_score':sum(p[0] for p in pred)/len(pred),'binomial_mean_log_score':sum(p[1] for p in pred)/len(pred)},
      'directory':30,'noObservations':0,'baseline_fit_status':{str(k):v['fit_status'] for k,v in baselines.items()}}

def main():
    payload=build_payload()
    assert payload['data_kind']=='synthetic' and len(payload['employees'])==30 and len(payload['grid'])==108
    template=(ROOT/'dashboards/dashboard.template.html').read_text(encoding='utf-8')
    fragment=template.replace('__DASHBOARD_DATA_JSON__',json.dumps(payload,separators=(',',':'))).replace('__DASHBOARD_SCRIPT__',(ROOT/'dashboards/dashboard.js').read_text(encoding='utf-8'))
    css=(ROOT/'dashboards/demo.css').read_text(encoding='utf-8')
    header='<!doctype html><html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><meta name="referrer" content="no-referrer"><title>Stark Overflow · Synthetic model demo</title><style>'+css+'</style></head><body><main><header class="intro"><h1>Discount-policy review prioritization</h1><p>Explore the actual temporal model on invented employees and observations. Every record below is synthetic. Scores depend on assumptions and do not establish a policy violation.</p></header>'
    page=header+fragment+'</main></body></html>\n'
    (ROOT/'dashboards/model-demo.html').write_text(page,encoding='utf-8')
    print('Generated dashboards/model-demo.html: 30 invented employees, 108 scenarios, no private inputs.')
    print('Open it in a browser. D3 loads from its pinned public CDN; model generation and tests make no data-service requests.')

if __name__=='__main__':main()
