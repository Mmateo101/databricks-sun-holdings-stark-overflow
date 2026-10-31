-- Authorized SQL editor examples. Replace ${model_namespace} and ${model_run_id}
-- with your configured three-part model namespace/run. These queries are read-only.
-- Namespace example: MY_CATALOG.MY_MODEL_SCHEMA (two parts).

SELECT employee_id,location_id,week_start,model_observation_status,
 activity_successes,activity_trials,reference_prior,reference_probability,
 sensitivity_min,sensitivity_max
FROM ${model_namespace}.scenario_week_history
WHERE model_run_id='${model_run_id}'
ORDER BY employee_id,location_id,week_start;

SELECT model_observation_status,count(*) AS employee_weeks
FROM ${model_namespace}.scenario_week_history
WHERE model_run_id='${model_run_id}'
GROUP BY model_observation_status;

SELECT model_run_id,heldout_rows,bb_mean_log_score,binomial_mean_log_score
FROM ${model_namespace}.scenario_diagnostics
WHERE model_run_id='${model_run_id}';

-- Latest independent review evaluation. Metrics remain NULL while required reviews are unresolved.
SELECT batch_id,outcomes_version,result_json
FROM ${model_namespace}.review_pilot_evaluations
ORDER BY evaluated_at DESC;
