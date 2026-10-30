"""Declared conditional/temporal scenarios; never claims empirical fraud calibration."""
from datetime import date, timedelta
from functools import lru_cache
from itertools import product
import math
from statistics import median, pvariance
from count_model import beta_binomial_log_pmf, validate_counts
from inference import predict, probability, update


def transitions(base_rate, half_life):
    probability(base_rate)
    if not 0 < base_rate < 1 or not math.isfinite(half_life) or half_life < 0:
        raise ValueError('Interior base rate and nonnegative finite half-life required')
    memory = 0.0 if half_life == 0 else 2**(-1/half_life)
    return {'initial_probability':base_rate,'persistence':base_rate+(1-base_rate)*memory,
            'onset':base_rate*(1-memory),'memory_coefficient':memory}


def scenario_grid(config):
    if config.get('status')!='assumption_sensitivity_only':
        raise ValueError('Explicit assumption sensitivity status required')
    fields=('weekly_base_rate','memory_half_life_weeks','activity_odds_multiplier','concentration_multiplier')
    values=[config['weekly_base_rates'],config['memory_half_lives_weeks'],
            config['activity_odds_multipliers'],config['concentration_multipliers']]
    if any(not v or len(set(v))!=len(v) for v in values):
        raise ValueError('Scenario values must be nonempty and unique')
    result=[]
    for index, combination in enumerate(product(*values)):
        row={k:float(v) for k,v in zip(fields,combination)}
        if any(not math.isfinite(row[k]) or row[k]<=0 for k in fields[2:]):
            raise ValueError('Activity and concentration multipliers must be positive')
        row.update(transitions(row['weekly_base_rate'],row['memory_half_life_weeks']))
        row.update(scenario_index=index,scenario_id=f's{index:03}',
                   is_reference=all(row[k]==config['reference'][k] for k in fields),
                   parameter_status='assumption_sensitivity_only')
        result.append(row)
    if sum(r['is_reference'] for r in result)!=1: raise ValueError('One reference scenario required')
    return result


def observation_status(row):
    k,n=int(row['activity_successes']),int(row['activity_trials'])
    validate_counts(k,n)
    if row['is_partial_week'] or row['location_source_days']!=7:
        return 'prior_only_partial_calendar'
    if any(row[name] for name in ('action_only_checks','multi_actor_checks','unknown_actor_checks','incomplete_discount_checks')):
        return 'prior_only_attribution_or_amount_coverage'
    if row['actor_positive_checks']!=k or n==0:
        return 'prior_only_opportunity_proxy_incomplete'
    return 'recorded_scope_zero_positive_actions' if k==0 else 'assumption_conditioned_activity'


def training_boundary(rows, weeks):
    if type(weeks) is not int or weeks<1: raise ValueError('Positive training week count required')
    full=sorted({r['week_start'] for r in rows if not r['is_partial_week'] and r['location_source_days']==7})
    if len(full)<=weeks: raise ValueError('Need complete weeks after the training period')
    return full[:weeks],full[weeks-1]+timedelta(days=7)


def binomial_log_pmf(k,n,mean):
    validate_counts(k,n)
    if not 0<mean<1: raise ValueError('Interior binomial mean required')
    return (math.lgamma(n+1)-math.lgamma(k+1)-math.lgamma(n-k+1)
            + k*math.log(mean)+(n-k)*math.log1p(-mean))


@lru_cache(maxsize=500000)
def activity_log_ratio(k,n,mean,kappa,odds_multiplier,concentration_multiplier):
    """Class 1 is positive-truncated to respect the selected event's support."""
    validate_counts(k,n)
    if n==0 or k==0: raise ValueError('Positive observed activity required for this likelihood ratio')
    if not 0<mean<1 or any(not math.isfinite(v) or v<=0 for v in (kappa,odds_multiplier,concentration_multiplier)):
        raise ValueError('Valid interior baseline and positive multipliers required')
    concentration=kappa*concentration_multiplier
    elevated=odds_multiplier*mean/(1-mean+odds_multiplier*mean)
    log0=beta_binomial_log_pmf(k,n,mean*concentration,(1-mean)*concentration)
    log1=beta_binomial_log_pmf(k,n,elevated*concentration,(1-elevated)*concentration)
    log_zero=beta_binomial_log_pmf(0,n,elevated*concentration,(1-elevated)*concentration)
    # -expm1 remains accurate when the zero mass is close to one.
    positive_mass=-math.expm1(min(log_zero,-1e-15))
    return log1-math.log(positive_mass)-log0


def fit_background(rows, fit_config):
    """MLE of unlabeled counts only; SciPy is already installed on Databricks."""
    import numpy as np
    from scipy.optimize import minimize
    from scipy.special import expit, betaln, gammaln
    pairs=[(int(r['activity_successes']),int(r['activity_trials'])) for r in rows]
    for k,n in pairs: validate_counts(k,n)
    if len(pairs)<2 or not 0<sum(k for k,n in pairs)<sum(n for k,n in pairs):
        raise ValueError('Insufficient interior background counts')
    k,n=np.asarray(pairs,dtype=float).T
    pooled=float(k.sum()/n.sum())
    constant=gammaln(n+1)-gammaln(k+1)-gammaln(n-k+1)
    def objective(x):
        m=float(expit(x[0])); c=math.exp(float(x[1]))
        return -float(np.sum(constant+betaln(k+m*c,n-k+(1-m)*c)-betaln(m*c,(1-m)*c)))
    bounds=[tuple(fit_config['logit_mean_bounds']),tuple(fit_config['log_concentration_bounds'])]
    logit=max(bounds[0][0],min(bounds[0][1],math.log(pooled/(1-pooled))))
    fits=[minimize(objective,[logit,math.log(c)],method='L-BFGS-B',bounds=bounds,
                   options={'maxiter':300,'ftol':1e-11}) for c in fit_config['initial_concentrations']]
    candidates=[r for r in fits if r.success and math.isfinite(float(r.fun))]
    if not candidates: raise ValueError('Background optimizer did not converge')
    best=min(candidates,key=lambda r:r.fun)
    mean=float(expit(best.x[0])); kappa=math.exp(float(best.x[1]))
    if float(best.fun)>min(objective([logit,math.log(c)]) for c in fit_config['initial_concentrations'])+1e-6:
        raise ValueError('Optimizer failed starting-point check')
    boundary=any(abs(float(x)-lo)<1e-4 or abs(float(x)-hi)<1e-4 for x,(lo,hi) in zip(best.x,bounds))
    return dict(mean=mean,kappa=kappa,binomial_mean=pooled,training_rows=len(rows),
                training_trials=int(n.sum()),training_successes=int(k.sum()),training_nll=float(best.fun),
                optimizer_boundary=boundary,fit_status='mle_boundary' if boundary else 'mle_converged')


def filter_history(rows,scenarios,baselines,cutoff):
    """Forward filtering only. A grid envelope is sensitivity, not a posterior CI."""
    if not scenarios or sum(s['is_reference'] for s in scenarios)!=1: raise ValueError('Reference scenario required')
    reference=next(i for i,s in enumerate(scenarios) if s['is_reference'])
    identities={}; result=[]; seen=set()
    for row in sorted(rows,key=lambda r:(r['employee_id'],r['location_id'],r['week_start'])):
        week=row['week_start']
        if isinstance(week,str): week=date.fromisoformat(week)
        if week.weekday()!=3: raise ValueError('Thursday weeks required')
        identity=(row['employee_id'],row['location_id'])
        key=(*identity,week)
        if key in seen: raise ValueError('Duplicate employee/location/week')
        seen.add(key)
        previous=identities.get(identity)
        if previous and week<=previous[0]: raise ValueError('Duplicate or unordered week')
        if week<cutoff:
            result.append({**row,'model_observation_status':'background_training_period',
                           'reference_probability':None,'reference_prior':None,'sensitivity_min':None,
                           'sensitivity_max':None,'sensitivity_median':None,'sensitivity_variance':None,
                           'scenario_probabilities':None,'scenario_priors':None,'scenario_log_ratios':None,
                           'elapsed_model_weeks':None,'baseline_mean':None,'baseline_kappa':None})
            # Training rows do not initialize or update a target-state filter.
            continue
        status=observation_status(row)
        baseline=baselines.get(row['location_id'],baselines[None])
        elapsed=None if previous is None else (week-previous[0]).days//7
        priors=[]; posteriors=[]; ratios=[]
        for i,s in enumerate(scenarios):
            prior=s['initial_probability'] if previous is None else predict(previous[1][i],s['persistence'],s['onset'],elapsed)
            ratio=None
            if status=='recorded_scope_zero_positive_actions':
                posterior=0.0
            elif status=='assumption_conditioned_activity':
                ratio=activity_log_ratio(int(row['activity_successes']),int(row['activity_trials']),baseline['mean'],baseline['kappa'],s['activity_odds_multiplier'],s['concentration_multiplier'])
                posterior=update(prior,ratio)
            else:
                posterior=prior
            priors.append(prior);posteriors.append(posterior);ratios.append(ratio)
        identities[identity]=(week,posteriors)
        result.append({**row,'model_observation_status':status,'reference_probability':posteriors[reference],
                       'reference_prior':priors[reference],'sensitivity_min':min(posteriors),
                       'sensitivity_max':max(posteriors),'sensitivity_median':median(posteriors),
                       'sensitivity_variance':pvariance(posteriors),'scenario_probabilities':posteriors,
                       'scenario_priors':priors,'scenario_log_ratios':ratios,'elapsed_model_weeks':elapsed,
                       'baseline_mean':baseline['mean'],'baseline_kappa':baseline['kappa']})
    return result
