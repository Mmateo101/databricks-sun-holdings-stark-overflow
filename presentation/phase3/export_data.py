"""Every number the Phase 3 deck shows, exported to data.json. Read-only queries on applebees_semantic.
Employees and restaurants are anonymized here (Employee A, Restaurant 1); IDs never leave this script."""
import json, os, sys
from pathlib import Path
import numpy as np, pandas as pd
from scipy import stats

HERE = Path(__file__).parent
sys.path.insert(0, str(HERE))
from dbx import sql
from queries import EMPLOYEE_TOTALS

M = os.environ['DECK_MODEL_SCHEMA']  # e.g. applebees_semantic.<your model schema>
RUN = sql(f"SELECT max_by(model_run_id, completed_at) r FROM {M}.review_list_runs").r[0]
SHOW, LAST = int(os.environ['DECK_SHOWCASE_EMPLOYEE_ID']), os.environ.get('DECK_LAST_WEEK', '2026-08-13')  # shown as 'Employee A'
out = {}
def _n(s):
    try:
        return pd.to_numeric(s)
    except (ValueError, TypeError):
        return s
num = lambda d: d.apply(lambda s: s if s.name in ('week_start', 'business_date') else _n(s))

# ---------- headline ----------
h = sql("""SELECT (SELECT count(*) FROM applebees_semantic.silver.checks) checks,
  (SELECT sum(gross_price) FROM applebees_semantic.silver.check_items) sales,
  (SELECT sum(amount) FROM applebees_semantic.silver.discount_events) discounts,
  (SELECT count(DISTINCT location_id) FROM applebees_semantic.silver.checks) stores,
  (SELECT count(DISTINCT business_date) FROM applebees_semantic.silver.checks) days,
  (SELECT count(DISTINCT employee_id) FROM applebees_semantic.gold.fraud_employee_week) employees,
  (SELECT count(*) FROM applebees_semantic.gold.fraud_employee_week) employee_weeks,
  (SELECT count(DISTINCT manager_id) FROM applebees_semantic.gold.fraud_manager_week) managers,
  (SELECT count(*) FROM applebees_semantic.gold.fraud_manager_week) manager_weeks""")
out['headline'] = {k: float(v) for k, v in h.iloc[0].items()}

# ---------- inferential: same employee, discounted vs not discounted checks ----------
e = num(sql(EMPLOYEE_TOTALS))
e = e[(e.checks >= 100) & (e.discounted_checks >= 20) & (e.nondiscounted_checks >= 20)].copy()
e['dr'] = e.discount_amount / e.sales
q1, q3 = e.dr.quantile([.25, .75]); fence = q3 + 1.5 * (q3 - q1); e['out'] = e.dr > fence
e['con'] = e.cnt_d / e.discounted_checks; e['sin'] = e.cnt_n / e.nondiscounted_checks; e['gap'] = e.con - e.sin
def ci(x, conf=.95):
    m, se = x.mean(), x.std(ddof=1) / np.sqrt(len(x)); t = stats.t.ppf(.5 + conf / 2, len(x) - 1)
    return float(m), float(m - t * se), float(m + t * se)
paired = {}
for k, g in [('all', e), ('rest', e[~e.out]), ('out', e[e.out])]:
    m, lo, hi = ci(g.gap)
    paired[k] = {'n': int(len(g)), 'con': float(g.con.mean()), 'sin': float(g.sin.mean()), 'gap': m, 'lo': lo, 'hi': hi,
                 'share_up': float((g.gap > 0).mean())}
tt = stats.ttest_rel(e.con, e.sin)
paired['t_paired'] = float(tt.statistic); paired['df_paired'] = int(len(e) - 1); paired['p_paired'] = float(tt.pvalue)
w = stats.ttest_ind(e.gap[e.out], e.gap[~e.out], equal_var=False)
va, vb = e.gap[e.out].var(ddof=1) / e.out.sum(), e.gap[~e.out].var(ddof=1) / (~e.out).sum()
dfw = (va + vb) ** 2 / (va ** 2 / (e.out.sum() - 1) + vb ** 2 / ((~e.out).sum() - 1))
out['tests'] = {'fence': float(fence), 'n': int(len(e)), 'n_out': int(e.out.sum()), 'paired': paired,
                'welch': {'t': float(w.statistic), 'df': float(dfw), 'p': float(w.pvalue), 'crit': float(stats.t.ppf(.975, dfw)),
                          'diff': float(e.gap[e.out].mean() - e.gap[~e.out].mean())},
                'dr_hist': np.histogram(e.dr.clip(upper=.15), bins=50, range=(0, .15))[0].tolist(),
                'dr_hist_out': np.histogram(e.dr[e.out].clip(upper=.15), bins=50, range=(0, .15))[0].tolist()}

# ---------- descriptive: discount types, outliers vs everyone else ----------
outs = ','.join(str(int(i)) for i in e.employee_id[e.out])
kept = ','.join(str(int(i)) for i in e.employee_id)
d = num(sql(f"""SELECT discount_name, CASE WHEN discount_employee_id IN ({outs}) THEN 1 ELSE 0 END o, count(*) n, sum(amount) amt
  FROM applebees_semantic.silver.discount_events WHERE discount_employee_id IN ({kept}) GROUP BY ALL"""))
pv = d.pivot_table(index='discount_name', columns='o', values=['n', 'amt'], aggfunc='sum', fill_value=0)
mix = pd.DataFrame({'n_rest': pv['n'][0], 'n_out': pv['n'][1], 'amt_rest': pv['amt'][0], 'amt_out': pv['amt'][1]})
mix['s_rest'] = mix.n_rest / mix.n_rest.sum(); mix['s_out'] = mix.n_out / mix.n_out.sum()
mix['times'] = mix.s_out / mix.s_rest
big = mix[(mix.n_rest + mix.n_out) >= 3000].sort_values('times', ascending=False)
out['types'] = [{'code': c, 'times': float(r.times), 's_out': float(r.s_out), 's_rest': float(r.s_rest), 'uses': int(r.n_rest + r.n_out)}
                for c, r in big.iterrows()]
# per-check discount on outliers vs rest, and share of discounted checks
out['types_ctx'] = {'disc_per_100_out': float(e[e.out].discounted_checks.sum() / e[e.out].checks.sum() * 100),
                    'disc_per_100_rest': float(e[~e.out].discounted_checks.sum() / e[~e.out].checks.sum() * 100),
                    'dr_out': float(e[e.out].discount_amount.sum() / e[e.out].sales.sum()), 'dr_rest': float(e[~e.out].discount_amount.sum() / e[~e.out].sales.sum())}

# ---------- Bayesian model + time series, Employee A ----------
s = num(sql(f"""SELECT r.week_start, r.priority, r.ts_status, r.bayes_probability p, r.bayes_plausible_min pmin, r.bayes_plausible_max pmax,
  r.bayes_percentile pct, r.checks, r.discount_share ds, r.store_discount_share sds, t.cusum_up / t.threshold cus, r.reasons
  FROM {M}.review_list_week r LEFT JOIN {M}.ts_employee_period t ON t.employee_id = r.employee_id AND t.week_start = r.week_start
   AND t.model_run_id = r.model_run_id AND t.indicator = 'discount_frequency'
  WHERE r.model_run_id = {RUN} AND r.employee_id = {SHOW} ORDER BY 1"""))
out['showcase'] = [{'week': str(r.week_start), 'p': None if pd.isna(r.p) else float(r.p), 'pmin': None if pd.isna(r.pmin) else float(r.pmin),
                    'pmax': None if pd.isna(r.pmax) else float(r.pmax), 'ds': float(r.ds), 'sds': float(r.sds),
                    'cus': None if pd.isna(r.cus) else float(r.cus), 'checks': int(r.checks)} for r in s.itertuples()]
out['showcase_reason'] = s.reasons.iloc[-1]

# ---------- weekly review list ----------
c = num(sql(f"SELECT week_start, priority, count(*) n FROM {M}.review_list_week WHERE model_run_id = {RUN} AND priority IS NOT NULL GROUP BY ALL"))
weeks = {}
for r in c.itertuples():
    weeks.setdefault(str(r.week_start), {'1': 0, '2': 0, '3': 0})[str(int(r.priority))] = int(r.n)
out['review_weeks'] = dict(sorted(weeks.items()))
prev = sorted(weeks)[-2]
top = num(sql(f"""SELECT priority, bayes_percentile, discount_share, store_discount_share, ts_status, reasons FROM {M}.review_list_week
  WHERE model_run_id = {RUN} AND week_start = '{LAST}' AND priority IS NOT NULL ORDER BY priority, bayes_percentile DESC LIMIT 6"""))
out['regional_rows'] = [{'who': f'Employee {chr(66 + i)}', 'priority': int(r.priority), 'ds': float(r.discount_share), 'sds': float(r.store_discount_share),
                         'status': r.ts_status, 'reason': r.reasons.split('. ')[0]} for i, r in enumerate(top.itertuples())]
out['email_counts'] = weeks[LAST]; out['email_prev'] = weeks[prev]

# ---------- manager email: one restaurant, this week vs last ----------
loc = int(sql(f"SELECT location_id l FROM applebees_semantic.gold.fraud_employee_week WHERE employee_id = {SHOW} GROUP BY 1 ORDER BY sum(checks) DESC LIMIT 1").l[0])
lw = num(sql(f"""SELECT date_sub(business_date, (dayofweek(business_date) + 2) % 7) week_start, sum(rate_gross_component) gross,
  sum(rate_discount_component) disc, sum(accepted_count) checks FROM applebees_semantic.gold.location_day
  WHERE location_id = {loc} GROUP BY 1 ORDER BY 1"""))
lw = lw[lw.week_start.astype(str) <= LAST].tail(2)
a, b = lw.iloc[-1], lw.iloc[0]
out['store_email'] = {'sales': float(a.gross), 'sales_prev': float(b.gross), 'dr': float(a.disc / a.gross), 'dr_prev': float(b.disc / b.gross),
                      'checks': int(a.checks), 'checks_prev': int(b.checks)}
hp = num(sql(f"""SELECT count(*) n FROM {M}.review_list_week WHERE model_run_id = {RUN} AND week_start = '{LAST}' AND priority = 1"""))
st = num(sql(f"""SELECT count(DISTINCT location_id) n FROM {M}.review_list_week WHERE model_run_id = {RUN} AND week_start = '{LAST}' AND priority = 1"""))
tot = num(sql(f"""SELECT date_sub(business_date, (dayofweek(business_date) + 2) % 7) week_start, sum(rate_gross_component) gross, sum(rate_discount_component) disc
  FROM applebees_semantic.gold.location_day GROUP BY 1 ORDER BY 1"""))
tot = tot[tot.week_start.astype(str) <= LAST].tail(2)
out['upper_email'] = {'disc': float(tot.iloc[-1].disc), 'disc_prev': float(tot.iloc[0].disc), 'dr': float(tot.iloc[-1].disc / tot.iloc[-1].gross),
                      'dr_prev': float(tot.iloc[0].disc / tot.iloc[0].gross), 'high': int(hp.n[0]), 'stores_high': int(st.n[0])}
out['last_week'] = LAST

# ---------- expedient: Employee A against store thresholds ----------
t = num(sql(f"""WITH w AS (SELECT * FROM applebees_semantic.gold.fraud_employee_week WHERE checks >= 30 AND location_id = {loc}),
  thr AS (SELECT week_start, percentile(discount_frequency, .95) t_freq, percentile(discount_frequency, .5) m_freq,
                 percentile(cash_ratio, .95) t_cash, percentile(cash_ratio, .5) m_cash FROM w GROUP BY 1)
  SELECT e.week_start, e.checks, e.discount_frequency freq, e.cash_ratio cash, e.full_comp_checks fc, e.discount_amount disc, e.sales,
         thr.t_freq, thr.m_freq, thr.t_cash, thr.m_cash
  FROM applebees_semantic.gold.fraud_employee_week e JOIN thr USING (week_start) WHERE e.employee_id = {SHOW} ORDER BY 1"""))
out['expedient'] = [{k: (str(v) if k == 'week_start' else (None if pd.isna(v) else float(v))) for k, v in r.items()} for r in t.to_dict('records')]

Path(HERE / 'data.json').write_text(json.dumps(out, indent=1, ensure_ascii=False), encoding='utf-8')
print(json.dumps({k: v for k, v in out.items() if k in ('tests', 'types_ctx', 'store_email', 'upper_email')}, indent=1, default=str)[:3500])
print([ (x['code'], round(x['times'], 2)) for x in out['types'][:12]])
