-- applebees_semantic.gold.fraud_manager_day: one row per manager, restaurant and business date.
-- A manager-day exists when the manager approved at least one discount or one void at that restaurant.
-- Manager = manager_id on discount_events (approver of a discount) and on silver.voids (approver of a void).
-- manager_id 0 means "not specified" (automatic loyalty and gift card discounts) and is left out.
-- Store totals come from gold.location_day. Every ratio keeps its numerator and denominator as columns.
-- ${target} is the table to write.

CREATE OR REPLACE TABLE ${target} AS
WITH approvals AS (
  SELECT manager_id, location_id, business_date, discount_employee_id, amount
  FROM applebees_semantic.gold.discount_events
  WHERE manager_id IS NOT NULL AND manager_id <> 0
),
appr_day AS (
  SELECT manager_id, location_id, business_date,
    count(*) AS approved_uses,
    sum(amount) AS approved_amount,
    count(DISTINCT discount_employee_id) AS approved_employees,
    count_if(discount_employee_id = manager_id) AS self_approved_uses
  FROM approvals
  GROUP BY ALL
),
top_emp AS (  -- approvals that went to the employee this manager approved most that day
  SELECT manager_id, location_id, business_date, max(n) AS top_employee_uses
  FROM (SELECT manager_id, location_id, business_date, discount_employee_id, count(*) AS n
        FROM approvals GROUP BY ALL)
  GROUP BY ALL
),
void_day AS (
  SELECT manager_id, location_id, business_date, count(*) AS approved_voids, sum(amount) AS approved_void_amount
  FROM applebees_semantic.silver.voids
  WHERE manager_id IS NOT NULL AND manager_id <> 0
  GROUP BY ALL
),
store_appr AS (  -- every approving manager of the restaurant that day (the peers)
  SELECT location_id, business_date, sum(amount) AS store_approved_amount,
    count(DISTINCT manager_id) AS store_managers
  FROM approvals
  GROUP BY ALL
),
keys AS (
  SELECT manager_id, location_id, business_date FROM appr_day
  UNION
  SELECT manager_id, location_id, business_date FROM void_day
)
SELECT k.business_date, k.manager_id, k.location_id,
  coalesce(a.approved_uses, 0) AS approved_uses,
  coalesce(a.approved_amount, 0) AS approved_amount,
  coalesce(a.approved_employees, 0) AS approved_employees,
  ld.gross_known_subtotal AS store_sales,
  ld.accepted_count AS store_checks,
  coalesce(a.approved_amount, 0) / nullif(ld.gross_known_subtotal, 0) AS approval_ratio,
  coalesce(a.self_approved_uses, 0) AS self_approved_uses,
  a.self_approved_uses / nullif(a.approved_uses, 0) AS self_approval_ratio,
  coalesce(t.top_employee_uses, 0) AS top_employee_uses,
  t.top_employee_uses / nullif(a.approved_uses, 0) AS concentration_ratio,
  coalesce(v.approved_voids, 0) AS approved_voids,
  coalesce(v.approved_void_amount, 0) AS approved_void_amount,
  coalesce(v.approved_voids, 0) * 100.0 / nullif(ld.accepted_count, 0) AS approved_voids_per_100_checks,
  coalesce(s.store_approved_amount, 0) AS store_approved_amount,
  coalesce(s.store_managers, 0) AS store_managers,
  a.approved_amount / nullif(s.store_approved_amount / nullif(s.store_managers, 0), 0) AS approval_vs_peers
FROM keys k
LEFT JOIN appr_day a USING (manager_id, location_id, business_date)
LEFT JOIN top_emp t USING (manager_id, location_id, business_date)
LEFT JOIN void_day v USING (manager_id, location_id, business_date)
LEFT JOIN store_appr s USING (location_id, business_date)
LEFT JOIN applebees_semantic.gold.location_day ld USING (location_id, business_date);
