-- Weekly review list: one row per employee and week (model run {{run}}).
-- priority 1 = top 5 % of the week in the Bayesian model AND rising or an unusual week against their own history;
-- 2 = one of the two; 3 = top 10 % or one unusual week. Reasons are written in plain words for the report.
-- The plausible range keeps only the scenarios where a violation means more discounting (odds multiplier >= 2).
WITH params AS (
  SELECT collect_list(scenario_index) AS idx FROM {{model}}.scenario_parameters
  WHERE model_run_id = '{{run}}' AND activity_odds_multiplier >= 2),
bayes AS (
  SELECT h.employee_id, h.location_id, h.week_start, h.reference_probability,
    array_min(filter(transform(h.scenario_probabilities, (p, i) -> IF(array_contains(params.idx, i), p, NULL)), x -> x IS NOT NULL)) AS plausible_min,
    array_max(filter(transform(h.scenario_probabilities, (p, i) -> IF(array_contains(params.idx, i), p, NULL)), x -> x IS NOT NULL)) AS plausible_max,
    h.activity_successes AS discounted_checks, h.activity_trials AS checks, h.baseline_mean AS store_discount_share,
    percent_rank() OVER (PARTITION BY h.week_start ORDER BY h.reference_probability) AS bayes_percentile
  FROM {{model}}.scenario_week_history h CROSS JOIN params
  WHERE h.model_run_id = '{{run}}' AND h.model_observation_status = 'assumption_conditioned_activity'),
ts AS (
  SELECT employee_id, week_start, status AS ts_status, top_driver, period_weeks
  FROM {{model}}.ts_employee_week WHERE model_run_id = '{{run}}'),
ts_reason AS (
  SELECT employee_id, week_start,
    concat_ws('; ', sort_array(collect_list(named_struct(
      'r', -observed / expected,
      't', CASE indicator WHEN 'discount_frequency' THEN 'discounts' WHEN 'full_comp' THEN 'fully comped checks'
                          WHEN 'discount_void' THEN 'checks with a discount and a void' ELSE 'voided items' END
           || ' ' || format_number(observed / expected, 1) || 'x their usual (' || CAST(CAST(observed AS INT) AS STRING)
           || ' vs ' || format_number(expected, 1) || ' expected)'))).t) AS ts_reasons
  FROM {{model}}.ts_employee_period
  WHERE model_run_id = '{{run}}' AND evaluable AND expected > 0 AND observed / expected >= 1.5 AND surprise_up < 0.05
  GROUP BY ALL)
SELECT b.week_start, b.employee_id, e.employee_name, b.location_id, l.location_name,
  round(b.reference_probability, 4) AS bayes_probability, round(b.bayes_percentile, 4) AS bayes_percentile,
  round(b.plausible_min, 4) AS bayes_plausible_min, round(b.plausible_max, 4) AS bayes_plausible_max,
  b.checks, b.discounted_checks, round(b.discounted_checks / b.checks, 4) AS discount_share,
  round(b.store_discount_share, 4) AS store_discount_share,
  coalesce(t.ts_status, 'not_evaluated') AS ts_status, t.top_driver AS ts_top_driver,
  CASE WHEN b.bayes_percentile >= 0.95 AND t.ts_status IN ('rising', 'spike') THEN 1
       WHEN b.bayes_percentile >= 0.95 OR t.ts_status = 'rising' THEN 2
       WHEN b.bayes_percentile >= 0.90 OR t.ts_status = 'spike' THEN 3 END AS priority,
  concat_ws('. ',
    CASE WHEN b.bayes_percentile >= 0.90 THEN 'Discounts on ' || format_number(100 * b.discounted_checks / b.checks, 0)
      || '% of checks vs ' || format_number(100 * b.store_discount_share, 0) || '% usual at the store (top '
      || CAST(greatest(1, ceil(100 * (1 - b.bayes_percentile))) AS STRING) || '% this week)' END,
    CASE WHEN t.ts_status = 'rising' THEN 'Rising against their own history' WHEN t.ts_status = 'spike' THEN 'Unusual week against their own history' END,
    initcap(substr(r.ts_reasons, 1, 1)) || substr(r.ts_reasons, 2)) AS reasons
FROM bayes b
LEFT JOIN ts t ON t.employee_id = b.employee_id AND t.week_start = b.week_start
LEFT JOIN ts_reason r ON r.employee_id = b.employee_id AND r.week_start = b.week_start
LEFT JOIN (SELECT employee_id, max_by(employee_name, location_id) AS employee_name FROM {{gold}}.silver_employees
           WHERE generation_id = '{{run}}' GROUP BY employee_id) e ON e.employee_id = b.employee_id
LEFT JOIN (SELECT location_id, max(location_name) AS location_name FROM {{gold}}.silver_locations
           WHERE generation_id = '{{run}}' GROUP BY location_id) l ON l.location_id = b.location_id
