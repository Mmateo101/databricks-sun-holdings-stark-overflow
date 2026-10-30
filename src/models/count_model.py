"""Beta rate uncertainty and beta-binomial count observations, not fraud labels."""
import math


def validate_counts(k, n, alpha=1.0, beta=1.0):
    if type(k) is not int or type(n) is not int or not 0 <= k <= n:
        raise ValueError("Counts must be integers with 0 <= k <= n")
    if any(not math.isfinite(v) or v <= 0 for v in (alpha, beta)):
        raise ValueError("Beta shapes must be finite and positive")


def beta_binomial_log_pmf(k, n, alpha, beta):
    validate_counts(k, n, alpha, beta)
    return (math.lgamma(n+1)-math.lgamma(k+1)-math.lgamma(n-k+1)
            + math.lgamma(k+alpha)+math.lgamma(n-k+beta)
            - math.lgamma(n+alpha+beta)+math.lgamma(alpha+beta)
            - math.lgamma(alpha)-math.lgamma(beta))


def _fraction(a, b, x):
    # Modified Lentz evaluation of the incomplete-beta continued fraction.
    tiny = 1e-300
    c = 1.0
    d = 1.0-(a+b)*x/(a+1)
    d = 1.0/(d if abs(d) > tiny else tiny)
    result = d
    for m in range(1, 501):
        for step in (m*(b-m)*x/((a+2*m-1)*(a+2*m)),
                     -(a+m)*(a+b+m)*x/((a+2*m)*(a+2*m+1))):
            d = 1+step*d
            c = 1+step/c
            d = 1.0/(d if abs(d) > tiny else tiny)
            c = c if abs(c) > tiny else tiny
            delta = d*c
            result *= delta
        if abs(delta-1) < 3e-14:
            return result
    raise ArithmeticError("Incomplete beta did not converge")


def beta_cdf(x, a, b):
    validate_counts(0, 0, a, b)
    if not math.isfinite(x) or not 0 <= x <= 1:
        raise ValueError("Beta argument outside [0,1]")
    if x in (0, 1):
        return float(x)
    front = math.exp(math.lgamma(a+b)-math.lgamma(a)-math.lgamma(b)
                     + a*math.log(x)+b*math.log1p(-x))
    value = (front*_fraction(a, b, x)/a if x < (a+1)/(a+b+2)
             else 1-front*_fraction(b, a, 1-x)/b)
    return min(1.0, max(0.0, value))


def beta_quantile(p, a, b):
    if not math.isfinite(p) or not 0 < p < 1:
        raise ValueError("Quantile probability must lie inside (0,1)")
    lo, hi = 0.0, 1.0
    for _ in range(55):
        mid = (lo+hi)/2
        if beta_cdf(mid, a, b) < p:
            lo = mid
        else:
            hi = mid
    return (lo+hi)/2


def summarize_rate(k, n, alpha=1.0, beta=1.0):
    """Fresh per-week posterior; no implicit cumulative or temporal update."""
    validate_counts(k, n, alpha, beta)
    a, b = alpha+k, beta+n-k
    s = a+b
    result = {"successes": k, "trials": n, "prior_alpha": float(alpha),
              "prior_beta": float(beta), "posterior_alpha": a, "posterior_beta": b,
              "rate_mean": None, "rate_variance": None, "rate_lower_95": None,
              "rate_upper_95": None, "predictive_trials": n,
              "predictive_count_mean": None, "predictive_count_variance": None,
              "rate_status": "no_evaluable_trials"}
    if n:
        result.update(rate_mean=a/s, rate_variance=a*b/(s*s*(s+1)),
                      rate_lower_95=beta_quantile(.025, a, b),
                      rate_upper_95=beta_quantile(.975, a, b),
                      predictive_count_mean=n*a/s,
                      predictive_count_variance=n*a*b*(s+n)/(s*s*(s+1)),
                      rate_status="exploratory_reference_prior")
    return result
