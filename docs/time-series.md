# Employee time series

The second objective of the project: compare every employee **against themselves over time**. Each period the
employee is labelled `rising`, `falling`, `spike`, `stable` or `insufficient_history`, with the indicator that drives it.
It runs as the `score_time_series` task of the weekly Job (`resources/jobs/weekly_fraud_model.yml`), after `build_gold`.

Code: `src/models/time_series.py` (method) and `src/models/score_time_series.py` (Job notebook).
Parameters: `src/models/time_series.json`. Tests: `tests/test_time_series.py` (synthetic data only).

## Question

> Is this employee, this week, behaving differently from how they usually behave, beyond what is happening to their whole store?

## Indicators

| Indicator | Count / checks | Distribution |
|---|---|---|
| `discount_frequency` | checks with a positive discount | beta-binomial |
| `full_comp` | checks with discount ≥ gross sales | beta-binomial |
| `discount_void` | discounted checks with at least one voided item | beta-binomial |
| `voids` | voided items | negative binomial |

A check belongs to the employee who took its first payment (gift card sales excluded), as in the gold fraud tables.

## Method

1. **Store effect.** The expected count for the employee comes from the *other* employees of the same store, week,
   daypart (lunch, afternoon, dinner, late) and channel (dine-in, off-premise, delivery). A promotion or a shift change
   moves the expectation, not the employee's score. Cells with fewer than 30 checks fall back to the store-week.
2. **Personal normal.** The employee's ratio to that expectation over the previous 8 weeks, leaving out the 2 most recent
   weeks, shrunk toward 1 with an empirical-Bayes gamma prior. While a change is building up (CUSUM above half the
   threshold) the normal is frozen, so a slow drift does not become the new normal.
3. **Adaptive period.** Employees with ≥ 40 checks per week are evaluated weekly, 20–39 every 2 weeks, fewer every 4 weeks.
   Counts are summed, never averaged. The first and last fraud weeks are partial and stay out of the calculation.
4. **Surprise.** Tail probabilities of the observed count under the personal normal (`surprise_up`, `surprise_down`).
5. **Sustained change.** A likelihood-ratio CUSUM per indicator: each period adds
   `log P(count | rate × 2) − log P(count | usual rate)`. Small samples add little evidence.
6. **Thresholds.** One threshold per indicator, set so each labels at most ¼ of a 3 % budget of evaluable periods.
   A noisy indicator cannot raise the threshold of the others.

Minimum history: 3 weeks with activity and 40 checks in the baseline window.

## Output tables (model schema)

| Table | Grain |
|---|---|
| `ts_employee_period` | employee × period × indicator: observed, store expectation, personal ratio, expected, surprise, CUSUM, threshold |
| `ts_employee_week` | employee × period: status, top driver, CUSUM as a share of its threshold |
| `ts_model_runs` | one row per Job run: thresholds, fitted parameters, alarm rate |

## Validation (development sandbox, real data, 2026-11-18)

Calibrated on 16,151 evaluable employee-periods: 2.4 % labelled `rising`. Tests on 300 weekly employees with injected changes:

| Injected change | Detected within 6 weeks | Median delay |
|---|---|---|
| +3 points of discount-and-void checks, at once | 96 % | 3 weeks |
| +3 points of discount-and-void checks, gradually | 85 % | 4 weeks |
| +3 points of full comps, at once | 44 % | 5 weeks |
| +3 points of full comps, gradually | 19 % | 6 weeks |

- A store-wide promotion did not raise the share of employees labelled `rising`.
- A simulated shift change to dinner raised false alarms to 9.8 % without the daypart × channel expectation, and 4.5 % with it.
- Freezing the normal detected more gradual changes (17 % vs 7 % for full comps).
- The ranking of employees was stable when changing the window (6 or 10 weeks), the change factor (1.5 or 3) or the gap
  (Spearman 0.92–0.997).

## Limits

- 16 full weeks: about 30 % of employees never collect enough history. Coverage grows with more weeks of data.
- Full comps change by only a few checks per week at these volumes; the time series detects them slowly.
  Comparison with peers covers that indicator better.
- An employee who has always been high is not `rising`; peer comparison covers that case.
- Thresholds come from alarm rates and injected changes, not from reviewed fraud cases.
