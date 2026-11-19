"""Employee time series: is each employee changing against their own history, beyond what their store did?

Input: one row per employee and fraud week (Thursday to Wednesday) with checks `n`, counts `k_<indicator>` and
the store expectation `e_<indicator>` (other employees of the same store, week, daypart and channel).
Output: one row per employee, period and indicator, plus a status per employee and period.
Method and calibration: docs/time-series.md. No fraud accuracy is claimed; thresholds are set by alarm rate.
"""
import math
import numpy as np
import pandas as pd
from scipy import optimize, special, stats


def logpmf(k, n, mu, phi, family):
    if family == 'bb':
        p = np.clip(mu / np.maximum(n, 1), 1e-4, 0.995)
        return stats.betabinom.logpmf(k, n, p * phi, (1 - p) * phi)
    mu = np.maximum(mu, 1e-3)
    return stats.nbinom.logpmf(k, phi, phi / (phi + mu))


def tails(k, n, mu, phi, family):
    """P(X >= k), P(X <= k) and a standardized residual under the employee's usual behavior."""
    if family == 'bb':
        p = np.clip(mu / np.maximum(n, 1), 1e-4, 0.995)
        d = stats.betabinom(n, p * phi, (1 - p) * phi)
        var = n * p * (1 - p) * (n + phi) / (1 + phi)
        return d.sf(k - 1), d.cdf(k), (k - n * p) / np.sqrt(np.maximum(var, 1e-9))
    mu = np.maximum(mu, 1e-3)
    d = stats.nbinom(phi, phi / (phi + mu))
    return d.sf(k - 1), d.cdf(k), (k - mu) / np.sqrt(mu + mu ** 2 / phi)


def fit_alpha(K, E):
    """Employee-to-store ratio theta ~ Gamma(alpha, alpha): K ~ NegBin(mean E, size alpha), maximum likelihood."""
    K, E = np.asarray(K, float), np.asarray(E, float)
    K, E = K[E > 0], E[E > 0]
    def nll(la):
        a = math.exp(la)
        return -np.sum(special.gammaln(K + a) - special.gammaln(a) + a * np.log(a / (a + E)) + K * np.log(E / (a + E) + 1e-300))
    return math.exp(optimize.minimize_scalar(nll, bounds=(-3, 8), method='bounded').x)


def fit_phi(k, n, mu, family):
    return math.exp(optimize.minimize_scalar(lambda lp: -np.sum(logpmf(k, n, mu, math.exp(lp), family)),
                                             bounds=(-2, 10), method='bounded').x)


def prepare(frame, config):
    """Full weeks only (first and last are partial), adaptive period per employee, employees x periods arrays."""
    inds = list(config['indicators'])
    weeks = sorted(frame['week_start'].unique())
    if len(weeks) < 4:
        raise ValueError('At least four fraud weeks are required')
    usable = weeks[1:-1]
    f = frame[frame['week_start'].isin(usable)].copy()
    f['u'] = f['week_start'].map({w: i for i, w in enumerate(usable)})
    volume = f.groupby('employee_id')['n'].median()
    period = pd.Series(np.select([volume >= config['weekly_checks_for_1_week'], volume >= config['weekly_checks_for_2_weeks']], [1, 2], 4),
                       index=volume.index)
    location = f.sort_values('n').groupby('employee_id')['location_id'].last()
    cols = ['n'] + [f'{a}_{i}' for a in ('k', 'e') for i in inds]
    groups = {}
    for p in (1, 2, 4):
        g = f[f['employee_id'].isin(period.index[period == p])].copy()
        if g.empty:
            continue
        g['b'] = g['u'] // p
        T = math.ceil(len(usable) / p)
        emps = np.sort(g['employee_id'].unique())
        row = pd.Series(np.arange(len(emps)), index=emps)
        s = g.groupby(['employee_id', 'b'])[cols].sum()
        out = {c: np.zeros((len(emps), T)) for c in cols}
        r, b = row[s.index.get_level_values(0)].values, s.index.get_level_values(1).values
        for c in cols:
            out[c][r, b] = s[c].values
        out.update(emps=emps, p=p, T=T, weeks=[usable[min((t + 1) * p, len(usable)) - 1] for t in range(T)])
        groups[p] = out
    return groups, usable, [weeks[0], weeks[-1]], location


def fit_params(groups, config):
    params = {}
    for i, family in config['indicators'].items():
        K = np.concatenate([g[f'k_{i}'].sum(1) for g in groups.values()])
        E = np.concatenate([g[f'e_{i}'].sum(1) for g in groups.values()])
        a = fit_alpha(K, E)
        k = np.concatenate([g[f'k_{i}'].ravel() for g in groups.values()])
        n = np.concatenate([g['n'].ravel() for g in groups.values()])
        th = np.concatenate([np.repeat((g[f'k_{i}'].sum(1) + a) / (g[f'e_{i}'].sum(1) + a), g['T']) for g in groups.values()])
        e = np.concatenate([g[f'e_{i}'].ravel() for g in groups.values()])
        m = n > 0
        params[i] = dict(alpha=a, phi=fit_phi(k[m], n[m], e[m] * th[m], family))
    return params


def score(g, params, h, config, k_over=None, e_over=None):
    """Sequential likelihood-ratio CUSUM per indicator, vectorised over employees."""
    p, T, n = g['p'], g['T'], g['n']
    L = math.ceil(config['window_weeks'] / p)
    gap = math.ceil(config['gap_weeks'] / p) if config['gap_weeks'] else 0
    r = config['change_factor']
    res = {}
    for i, family in config['indicators'].items():
        K = (k_over or {}).get(i, g[f'k_{i}'])
        E = (e_over or {}).get(i, g[f'e_{i}'])
        a, phi, hi = params[i]['alpha'], params[i]['phi'], h[i]
        N = len(n)
        cu, cd, frozen = np.zeros(N), np.zeros(N), np.full(N, np.nan)
        out = {c: np.full((N, T), np.nan) for c in ('theta', 'mu', 'z', 'sup', 'sdn', 'lu', 'ld', 'cu', 'cd')}
        out['ok'] = np.zeros((N, T), bool)
        for t in range(T):
            lo, top = max(0, t - gap - L), t - gap
            if top > lo:
                bK, bE, bn = K[:, lo:top].sum(1), E[:, lo:top].sum(1), n[:, lo:top].sum(1)
                bw = (n[:, lo:top] > 0).sum(1) * p
            else:
                bK = bE = bn = bw = np.zeros(N)
            ok = (bw >= config['min_history_weeks']) & (bn >= config['min_history_checks']) & (n[:, t] > 0)
            theta = (bK + a) / (bE + a)
            if config['freeze_normal']:
                theta = np.where(np.isnan(frozen), theta, frozen)
            mu = E[:, t] * theta
            k, nn = K[:, t], n[:, t]
            sup, sdn, z = tails(k, nn, mu, phi, family)
            base = logpmf(k, nn, mu, phi, family)
            lu = logpmf(k, nn, mu * r, phi, family) - base
            ld = logpmf(k, nn, mu / r, phi, family) - base
            cu = np.where(ok, np.maximum(0, cu + lu), cu)
            cd = np.where(ok, np.maximum(0, cd + ld), cd)
            if config['freeze_normal']:
                frozen = np.where(cu > hi / 2, np.where(np.isnan(frozen), theta, frozen), np.nan)
            for c, v in (('theta', theta), ('mu', mu), ('z', z), ('sup', sup), ('sdn', sdn), ('lu', lu), ('ld', ld), ('cu', cu), ('cd', cd)):
                out[c][:, t] = np.where(ok, v, np.nan)
            out['ok'][:, t] = ok
        res[i] = out
    inds = list(config['indicators'])
    ok = np.any([res[i]['ok'] for i in inds], axis=0)
    up = np.max([np.where(res[i]['ok'], res[i]['cu'] / h[i], -np.inf) for i in inds], axis=0)
    down = np.max([np.where(res[i]['ok'], res[i]['cd'] / h[i], -np.inf) for i in inds], axis=0)
    spike_p = np.min([np.where(res[i]['ok'], res[i]['sup'], np.inf) for i in inds], axis=0)
    rising, falling = ok & (up >= 1), ok & (down >= 1)
    spike = ok & (spike_p < config['spike_probability'] / len(inds))
    status = np.where(~ok, 'insufficient_history', np.where(rising, 'rising', np.where(spike, 'spike', np.where(falling, 'falling', 'stable'))))
    status = np.where(n > 0, status, 'no_activity')
    driver = np.array(inds)[np.argmax([np.where(res[i]['ok'], res[i]['cu'] / h[i], -1) for i in inds], axis=0)]
    return dict(ind=res, ok=ok & (n > 0), rising=rising, status=status, driver=driver, up=up)


def calibrate(groups, params, config):
    """One threshold per indicator: each may label at most 1/len(indicators) of the target share of evaluable periods."""
    lo, hi, step = config['threshold_grid']
    grid = np.arange(lo, hi + step / 2, step)
    inds = list(config['indicators'])
    rates = {i: {} for i in inds}
    for h in grid:
        runs = {p: score(g, params, {i: float(h) for i in inds}, config) for p, g in groups.items()}
        for i in inds:
            ok = np.concatenate([r['ind'][i]['ok'].ravel() for r in runs.values()])
            cu = np.concatenate([r['ind'][i]['cu'].ravel() for r in runs.values()])
            rates[i][float(h)] = float((cu[ok] >= h).mean()) if ok.any() else 0.0
    budget = config['target_rising_rate'] / len(inds)
    return {i: next((h for h, v in rates[i].items() if v <= budget), float(grid[-1])) for i in inds}, rates


def run(frame, config):
    """Fit, calibrate and score. Returns per-indicator rows, per-employee rows and run facts."""
    groups, usable, partial, location = prepare(frame, config)
    params = fit_params(groups, config)
    h, _ = calibrate(groups, params, config)
    runs = {p: score(g, params, h, config) for p, g in groups.items()}
    rows, summary = [], []
    for p, rr in runs.items():
        g = groups[p]
        for t in range(g['T']):
            act = np.where(g['n'][:, t] > 0)[0]
            if not len(act):
                continue
            base = dict(week_start=g['weeks'][t], employee_id=g['emps'][act], period_weeks=p)
            summary.append(pd.DataFrame({**base, 'checks': g['n'][act, t], 'status': rr['status'][act, t],
                                         'top_driver': rr['driver'][act, t], 'max_cusum_share_of_threshold': rr['up'][act, t]}))
            for i in config['indicators']:
                o = rr['ind'][i]
                rows.append(pd.DataFrame({**base, 'indicator': i, 'observed': g[f'k_{i}'][act, t], 'trials': g['n'][act, t],
                    'store_expected': g[f'e_{i}'][act, t], 'personal_ratio': o['theta'][act, t], 'expected': o['mu'][act, t],
                    'z': o['z'][act, t], 'surprise_up': o['sup'][act, t], 'surprise_down': o['sdn'][act, t],
                    'llr_up': o['lu'][act, t], 'llr_down': o['ld'][act, t], 'cusum_up': o['cu'][act, t],
                    'cusum_down': o['cd'][act, t], 'threshold': h[i], 'evaluable': o['ok'][act, t]}))
    long = pd.concat(rows, ignore_index=True)
    short = pd.concat(summary, ignore_index=True)
    edge = frame[frame['week_start'].isin(partial)][['week_start', 'employee_id', 'n']].rename(columns={'n': 'checks'})
    edge = edge.assign(period_weeks=1, status='partial_week', top_driver=None, max_cusum_share_of_threshold=np.nan)
    short = pd.concat([short, edge[short.columns]], ignore_index=True)
    for f in (long, short):
        f['location_id'] = f['employee_id'].map(location)
    ok = np.concatenate([r['ok'].ravel() for r in runs.values()])
    ri = np.concatenate([r['rising'].ravel() for r in runs.values()])
    facts = dict(thresholds=h, params=params, rising_rate=float(ri[ok].mean()) if ok.any() else 0.0,
                 evaluable_periods=int(ok.sum()), employees={str(p): int(len(g['emps'])) for p, g in groups.items()},
                 full_weeks=len(usable))
    return long, short, facts
