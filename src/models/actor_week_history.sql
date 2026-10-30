WITH weekly AS (
 SELECT employee_id,location_id,week_start,
 count_if(is_payment_owner) AS assigned_checks,
 count_if(is_payment_owner AND amount_eligible AND NOT multi_actor_check AND NOT has_unknown_actor) AS activity_trials,
 count_if(is_payment_owner AND amount_eligible AND NOT multi_actor_check AND NOT has_unknown_actor AND positive_applications>0) AS activity_successes,
 count_if(positive_applications>0) AS actor_positive_checks,
 sum(positive_applications) AS actor_positive_applications,
 sum(actor_positive_amount) AS actor_positive_amount,
 count_if(positive_applications>0 AND NOT is_payment_owner) AS action_only_checks,
 count_if(multi_actor_check) AS multi_actor_checks,
 count_if(has_unknown_actor) AS unknown_actor_checks,
 count_if(positive_applications>0 AND is_full_comp AND NOT multi_actor_check AND NOT has_unknown_actor) AS full_comp_actor_checks,
 count_if(NOT discount_complete) AS incomplete_discount_checks,
 count(DISTINCT business_date) AS observed_activity_days
 FROM actor_checks WHERE employee_id IS NOT NULL GROUP BY ALL
),
calendar AS (
 SELECT location_id,date_sub(business_date,pmod(dayofweek(business_date)-5,7)) AS week_start,
 count(DISTINCT business_date) AS location_source_days
 FROM {facts} GROUP BY ALL
),
bounds AS (SELECT min(business_date) AS source_first_date,max(business_date) AS source_last_date FROM {facts}),
base AS (
 SELECT w.*, c.location_source_days,b.source_first_date,b.source_last_date,
 w.week_start<b.source_first_date OR date_add(w.week_start,6)>b.source_last_date AS is_partial_week,
 lag(w.week_start) OVER (PARTITION BY w.employee_id,w.location_id ORDER BY w.week_start) AS previous_observed_week
 FROM weekly w JOIN calendar c USING(location_id,week_start) CROSS JOIN bounds b
)
SELECT *,date_add(week_start,6) AS week_end,
 CAST(datediff(week_start,previous_observed_week)/7 AS INT) AS elapsed_weeks,
 CASE WHEN previous_observed_week IS NULL THEN 'first_observed'
 WHEN datediff(week_start,previous_observed_week)=7 THEN 'consecutive' ELSE 'unobserved_calendar_gap' END AS sequence_status,
 'discount_actor' AS attribution_role,'first_payment_owner_proxy' AS activity_opportunity_basis,
 'parameters_unresolved' AS weekly_risk_status,CAST(NULL AS DOUBLE) AS weekly_violation_probability
FROM base
