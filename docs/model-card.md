# Weekly policy-review model

## Decision and unit

Help managers find more independently verified policy-violating employee-weeks per review. The event is at least one recorded positive-discount application that violated an applicable policy during an employee–restaurant–Thursday week, including mistakes. The actor is the employee recorded as applying the discount. Intent and permanent employee character are outside the target.

The team's employee fraud-feature tables assign checks to the first payment owner. The model instead reconstructs positive discount actions from the recorded actor. First-payment ownership remains an explicit proxy for count opportunities. These roles must not be silently relabeled.

## Data and observation

`K` is positive-discount checks among `N` eligible opportunities for the actor. Money is converted to decimal before full-comp comparisons. Partial calendar coverage, action-only checks, unknown/multiple actors, incomplete amounts and incomplete proxy denominators have explicit statuses. A complete recorded week with no positive discount action has zero support for this recorded-scope event. An incomplete week supplies no count likelihood; its filtered estimate follows the predicted prior. Missing calendar weeks advance transitions without inventing clean observations.

Only one activity-count block supplies likelihood evidence. Available tips, amount, full-comp and candidate-policy indicators are not multiplied as independent evidence. Conditional independence and their joint distributions would need justification before extension.

## Background and conditional assumptions

Fit a location beta-binomial background on the first four complete weeks, with a pooled fallback for insufficient local data. Fitting estimates a mean `mu0` and concentration `kappa0` from unlabeled activity. Treating this background as no-violation behavior is an assumption; legitimate roles, promotions, channels and violations may be mixed.

The hypothetical violation state changes the activity mean's odds and excludes zero positive actions:

```text
odds(mu1) = activity_odds_multiplier * odds(mu0)
L0(k) = BetaBinomial(k | N, mu0*kappa, (1-mu0)*kappa)
L1(k) = BetaBinomial(k | N, mu1*kappa, (1-mu1)*kappa) / P1(K>0), k>=1
L1(0) = 0
```

The truncation is normalized. The temporal update uses `L1/L0`, not the observed discount rate or its Beta posterior mean.

## Time

For hypothetical weekly base rate `pi` and half-life `h`, let `rho=0` when `h=0`, otherwise `rho=2**(-1/h)`. Then:

```text
persistence = pi + (1-pi)*rho
onset = pi*(1-rho)
predicted_prior = pi + rho**elapsed_weeks*(previous_posterior-pi)
```

This parameterization has stationary rate `pi`. The reference `pi=.05,h=1` implies persistence `.525` and onset `.025`; these are declared assumptions, not estimated behavioral transition rates. Training weeks have no event estimate.

## Sensitivity and uncertainty

The 108 settings cross base rates 1/5/10%, half-lives 0/1/4 weeks, activity odds 0.5/1/2/4 and concentration multipliers 0.5/1/2. The minimum/maximum and unweighted grid variance describe sensitivity. They are not posterior credible intervals or posterior parameter variance.

`count_model.summarize_rate` separately provides a Beta observation-rate posterior and beta-binomial count prediction. Those distributions describe discount rates/counts under their stated prior, not uncertainty in the binary violation-event probability. Background MLE uncertainty is not fully propagated in this release.

## Evaluation and use

Compare count prediction with a binomial baseline on later weeks. Count predictive performance does not establish verified violation detection. The independent review pilot evaluates precision at a fixed review budget, sampling-weighted recall, probability scores and calibration comparisons. It never uses an old risk coefficient as ground truth. See [review protocol](review-protocol.md).

Use outputs to select records for investigation alongside source evidence and sensitivity. Probabilities are assumption dependent and not empirically calibrated. No measured fraud accuracy, financial savings, confirmed misconduct or automated personnel decision is claimed. This is a historical review model, not a forecast of next week's misconduct.

The source implements a finite temporal Bayesian filter; the small discrete multi-indicator engine is retained only as a synthetic arithmetic demonstration. See `config/synthetic.json` and `src/models/demo.py` for that separate example.
