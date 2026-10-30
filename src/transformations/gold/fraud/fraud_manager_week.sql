-- ${catalog}.gold.fraud_manager_week: one row per manager, restaurant and week (Thursday to Wednesday,
-- the same weeks as fraud_employee_week). Additive columns are sums of fraud_manager_day; distinct employees,
-- top-employee approvals and the peer group are recomputed from the events of the whole week; ratios are
-- recomputed from the weekly numerators and denominators (daily ratios are never averaged).
-- ${source} is the manager day table, ${target} the table to write. Run after fraud_manager_day.sql.

CREATE OR REPLACE TABLE ${target} AS
WITH d AS (
  SELECT *, date_sub(business_date, (dayofweek(business_date) + 2) % 7) AS week_start
  FROM ${source}
),
sums AS (
  SELECT week_start, manager_id, location_id,
    count(DISTINCT business_date) AS days_active,
    sum(approved_uses) AS approved_uses, sum(approved_amount) AS approved_amount,
    sum(store_sales) AS store_sales, sum(store_checks) AS store_checks,
    sum(self_approved_uses) AS self_approved_uses,
    sum(approved_voids) AS approved_voids, sum(approved_void_amount) AS approved_void_amount
  FROM d
  GROUP BY ALL
),
approvals AS (
  SELECT manager_id, location_id, discount_employee_id, amount,
    date_sub(business_date, (dayofweek(business_date) + 2) % 7) AS week_start
  FROM ${catalog}.gold.discount_events
  WHERE manager_id IS NOT NULL AND manager_id <> 0
),
emp AS (
  SELECT week_start, manager_id, location_id,
    count(DISTINCT discount_employee_id) AS approved_employees,
    max(n) AS top_employee_uses
  FROM (SELECT week_start, manager_id, location_id, discount_employee_id, count(*) AS n
        FROM approvals GROUP BY ALL)
  GROUP BY ALL
),
store_appr AS (
  SELECT week_start, location_id, sum(amount) AS store_approved_amount,
    count(DISTINCT manager_id) AS store_managers
  FROM approvals
  GROUP BY ALL
)
SELECT s.week_start, s.manager_id, s.location_id, s.days_active,
  s.approved_uses, s.approved_amount,
  coalesce(e.approved_employees, 0) AS approved_employees,
  s.store_sales, s.store_checks,
  s.approved_amount / nullif(s.store_sales, 0) AS approval_ratio,
  s.self_approved_uses,
  s.self_approved_uses / nullif(s.approved_uses, 0) AS self_approval_ratio,
  coalesce(e.top_employee_uses, 0) AS top_employee_uses,
  e.top_employee_uses / nullif(s.approved_uses, 0) AS concentration_ratio,
  s.approved_voids, s.approved_void_amount,
  s.approved_voids * 100.0 / nullif(s.store_checks, 0) AS approved_voids_per_100_checks,
  coalesce(p.store_approved_amount, 0) AS store_approved_amount,
  coalesce(p.store_managers, 0) AS store_managers,
  nullif(s.approved_amount, 0) / nullif(p.store_approved_amount / nullif(p.store_managers, 0), 0) AS approval_vs_peers
FROM sums s
LEFT JOIN emp e USING (week_start, manager_id, location_id)
LEFT JOIN store_appr p USING (week_start, location_id);
