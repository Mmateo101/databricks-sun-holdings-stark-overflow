# Weekly review list

The last task of the weekly Job, `build_review_list`, joins the two models into the list HR reviews every week.
Code: `src/models/build_review_list.py` and `src/models/review_list.sql`.

| Source | Question it answers |
|---|---|
| Bayesian model (`scenario_week_history`) | Is this employee discounting more than their store, this week? |
| Time series (`ts_employee_week`, `ts_employee_period`) | Is this employee changing against their own history? |

## Priority

| Priority | Rule |
|---|---|
| **1 · High** | Top 5 % of the week in the Bayesian model **and** rising or an unusual week in the time series |
| **2 · Medium** | One of the two: top 5 % in the Bayesian model, or rising in the time series |
| **3 · Watch** | Top 10 % in the Bayesian model, or one unusual week in the time series |

The percentile is computed within each week among employees with usable evidence. The table also keeps the
reference probability and a **plausible range**: the minimum and maximum across the scenarios where a violation means
more discounting (odds multiplier ≥ 2), leaving out the scenarios that contradict the model.

## Reasons in plain words

Each row has a `reasons` sentence, for example:

> Discounts on 37% of checks vs 13% usual at the store (top 1% this week). Rising against their own history.
> Checks with a discount and a void 27.5x their usual (4 vs 0.1 expected); fully comped checks 7.5x their usual (8 vs 1.1 expected).

Time series reasons list the indicators at least 1.5 times their expected count with a surprise below 5 %.

## Output tables (model schema)

| Table | Grain |
|---|---|
| `review_list_week` | employee × week: names, scores, time series status, priority, reasons |
| `review_list_runs` | one row per Job run: latest week and how many employees per priority |

A priority means **review first**, not proof of fraud. Thresholds are percentiles and alarm rates, not reviewed outcomes.
