-- Semantic layer, part 2: employee, manager and restaurant KPI tables with outlier flags (EDA method).
-- KPI: discount rate = discount amount / gross sales. Outlier: rate above Q3 + 1.5 x IQR among eligible rows.
-- Employee and manager ID 0 (not specified) are left out. Re-run after 01 and 02.
-- Assumptions (documented in the comments): employee sales = gross of the lines the employee rang;
-- manager sales = store gross on the days the manager approved at least one discount;
-- eligibility thresholds 50 checks and 2,000 sales (employees, as in the EDA) and 50 approvals (managers).
-- The EDA also removed "automatic" discounts; that list is not available, so all discounts are counted.

CREATE OR REPLACE TABLE applebees_semantic.semantic.kpi_employee
COMMENT 'One row per employee who rang sales or applied discounts in the study period. Discount rate, discount frequency and card tip rate, with an outlier flag (Q3 + 1.5 x IQR among employees with at least 50 checks and 2,000 in sales). Being an outlier signals risk to review, not proof of fraud. Synonyms: employee watchlist, server KPIs.'
AS WITH sales AS (
  SELECT employee_id, location_id, count(DISTINCT location_id, business_date, check_id) AS checks,
    count(DISTINCT business_date) AS active_days, count(DISTINCT date_trunc('WEEK', business_date)) AS active_weeks,
    sum(gross_price) AS gross_sales
  FROM applebees_semantic.silver.check_items WHERE employee_id <> 0
  GROUP BY employee_id, location_id
), sales_emp AS (
  SELECT employee_id, max_by(location_id, gross_sales) AS main_location_id, sum(checks) AS checks,
    sum(active_days) AS active_days, max(active_weeks) AS active_weeks, sum(gross_sales) AS gross_sales
  FROM sales GROUP BY employee_id
), disc AS (
  SELECT discount_employee_id AS employee_id, count(*) AS discount_uses,
    count(DISTINCT location_id, business_date, check_id) AS discounted_checks,
    sum(amount) AS discount_amount, count_if(manager_id = discount_employee_id) AS self_approved_uses
  FROM applebees_semantic.gold.discount_events WHERE discount_employee_id <> 0
  GROUP BY discount_employee_id
), tips AS (
  SELECT employee_id, sum(tip) AS card_tips, sum(amount - tip) AS card_billed
  FROM applebees_semantic.silver.payments WHERE is_credit_card AND employee_id <> 0
  GROUP BY employee_id
), base AS (
  SELECT coalesce(s.employee_id, d.employee_id) AS employee_id, s.main_location_id,
    coalesce(s.checks, 0) AS checks, coalesce(s.active_days, 0) AS active_days, coalesce(s.active_weeks, 0) AS active_weeks,
    coalesce(s.gross_sales, 0) AS gross_sales, coalesce(d.discount_uses, 0) AS discount_uses,
    coalesce(d.discounted_checks, 0) AS discounted_checks, coalesce(d.discount_amount, 0) AS discount_amount,
    coalesce(d.self_approved_uses, 0) AS self_approved_uses, t.card_tips, t.card_billed
  FROM sales_emp s FULL JOIN disc d ON d.employee_id = s.employee_id
  LEFT JOIN tips t ON t.employee_id = coalesce(s.employee_id, d.employee_id)
), rated AS (
  SELECT *, CAST(discount_amount / nullif(gross_sales, 0) AS DOUBLE) AS discount_rate,
    CAST(discount_uses * 100.0 / nullif(checks, 0) AS DOUBLE) AS discount_uses_per_100_checks,
    CAST(card_tips / nullif(card_billed, 0) AS DOUBLE) AS card_tip_rate,
    checks >= 50 AND gross_sales >= 2000 AS is_kpi_eligible
  FROM base
), fences AS (
  SELECT percentile_cont(0.25) WITHIN GROUP (ORDER BY discount_rate) AS q1,
    percentile_cont(0.5) WITHIN GROUP (ORDER BY discount_rate) AS median_rate,
    percentile_cont(0.75) WITHIN GROUP (ORDER BY discount_rate) AS q3
  FROM rated WHERE is_kpi_eligible
)
SELECT r.employee_id, e.employee_name, r.main_location_id AS location_id, l.location_name, e.primary_job_id,
  r.checks, r.active_days, r.active_weeks, r.gross_sales, r.discount_uses, r.discounted_checks, r.discount_amount,
  r.self_approved_uses, r.discount_rate, r.discount_uses_per_100_checks, r.card_tips, r.card_billed, r.card_tip_rate,
  r.is_kpi_eligible, f.median_rate AS peer_median_rate, f.q3 + 1.5 * (f.q3 - f.q1) AS outlier_threshold,
  r.is_kpi_eligible AND r.discount_rate > f.q3 + 1.5 * (f.q3 - f.q1) AS is_outlier,
  CASE WHEN r.is_kpi_eligible AND r.discount_rate > f.median_rate
    THEN CAST((r.discount_rate - f.median_rate) * r.gross_sales AS DECIMAL(38,2)) ELSE 0 END AS excess_discount_vs_median
FROM rated r CROSS JOIN fences f
LEFT JOIN applebees_semantic.silver.employees e ON e.employee_id = r.employee_id
LEFT JOIN applebees_semantic.silver.locations l ON l.location_id = r.main_location_id;

ALTER TABLE applebees_semantic.semantic.kpi_employee ALTER COLUMN employee_id COMMENT 'Employee ID. Primary key.';
ALTER TABLE applebees_semantic.semantic.kpi_employee ALTER COLUMN employee_name COMMENT 'Employee name. Personal data: show it only for watchlist or person-level questions.';
ALTER TABLE applebees_semantic.semantic.kpi_employee ALTER COLUMN location_id COMMENT 'Main restaurant of the employee (where most of the employee sales are). NULL when the employee only applied discounts.';
ALTER TABLE applebees_semantic.semantic.kpi_employee ALTER COLUMN location_name COMMENT 'Main restaurant name of the employee.';
ALTER TABLE applebees_semantic.semantic.kpi_employee ALTER COLUMN primary_job_id COMMENT 'Primary job code (only proxy for role).';
ALTER TABLE applebees_semantic.semantic.kpi_employee ALTER COLUMN checks COMMENT 'Checks where the employee rang at least one line.';
ALTER TABLE applebees_semantic.semantic.kpi_employee ALTER COLUMN active_days COMMENT 'Store-days with at least one line rung by the employee.';
ALTER TABLE applebees_semantic.semantic.kpi_employee ALTER COLUMN active_weeks COMMENT 'Weeks (of 17) with at least one line rung by the employee.';
ALTER TABLE applebees_semantic.semantic.kpi_employee ALTER COLUMN gross_sales COMMENT 'Gross sales of the lines the employee rang (before discounts). Denominator of the employee discount rate.';
ALTER TABLE applebees_semantic.semantic.kpi_employee ALTER COLUMN discount_uses COMMENT 'Discount applications made by the employee (item and check level).';
ALTER TABLE applebees_semantic.semantic.kpi_employee ALTER COLUMN discounted_checks COMMENT 'Distinct checks where the employee applied at least one discount.';
ALTER TABLE applebees_semantic.semantic.kpi_employee ALTER COLUMN discount_amount COMMENT 'Signed sum of the discounts applied by the employee. Numerator of the employee discount rate.';
ALTER TABLE applebees_semantic.semantic.kpi_employee ALTER COLUMN self_approved_uses COMMENT 'Discounts the employee applied and also approved as manager (same ID in both roles). A control weakness worth reviewing.';
ALTER TABLE applebees_semantic.semantic.kpi_employee ALTER COLUMN discount_rate COMMENT 'Employee discount rate = discount_amount / gross_sales. Main KPI of the EDA.';
ALTER TABLE applebees_semantic.semantic.kpi_employee ALTER COLUMN discount_uses_per_100_checks COMMENT 'Discount applications per 100 checks served. The EDA found outliers at 78 vs 24 for the rest.';
ALTER TABLE applebees_semantic.semantic.kpi_employee ALTER COLUMN card_tips COMMENT 'Tips received on credit card payments taken by the employee. Cash tips are not recorded.';
ALTER TABLE applebees_semantic.semantic.kpi_employee ALTER COLUMN card_billed COMMENT 'Amount billed on those card payments, tip excluded (payment amount minus tip).';
ALTER TABLE applebees_semantic.semantic.kpi_employee ALTER COLUMN card_tip_rate COMMENT 'Card tip rate = card_tips / card_billed.';
ALTER TABLE applebees_semantic.semantic.kpi_employee ALTER COLUMN is_kpi_eligible COMMENT 'True when the employee has at least 50 checks and 2,000 in gross sales. Only eligible employees are ranked and can be outliers.';
ALTER TABLE applebees_semantic.semantic.kpi_employee ALTER COLUMN peer_median_rate COMMENT 'Median discount rate of eligible employees (same value on every row).';
ALTER TABLE applebees_semantic.semantic.kpi_employee ALTER COLUMN outlier_threshold COMMENT 'Outlier cutoff Q3 + 1.5 x IQR of the eligible employee discount rates (same value on every row).';
ALTER TABLE applebees_semantic.semantic.kpi_employee ALTER COLUMN is_outlier COMMENT 'True when an eligible employee discount rate is above outlier_threshold. Signals risk, not proof of fraud.';
ALTER TABLE applebees_semantic.semantic.kpi_employee ALTER COLUMN excess_discount_vs_median COMMENT 'Money discounted above what the median rate would give: (discount_rate - peer_median_rate) x gross_sales, 0 when at or below the median. Estimate of money at stake.';

CREATE OR REPLACE TABLE applebees_semantic.semantic.kpi_manager
COMMENT 'One row per manager who approved discounts in the study period. Approved discount rate against the store sales of the days the manager approved discounts, with an outlier flag (Q3 + 1.5 x IQR among managers with at least 50 approvals). Synonyms: manager KPIs, approver, gerente.'
AS WITH approvals AS (
  SELECT manager_id, location_id, business_date, count(*) AS approvals, sum(amount) AS approved_amount,
    count(DISTINCT discount_employee_id) AS employees, count_if(manager_id = discount_employee_id) AS self_approved
  FROM applebees_semantic.gold.discount_events WHERE manager_id <> 0
  GROUP BY manager_id, location_id, business_date
), base AS (
  SELECT a.manager_id, max_by(a.location_id, a.approvals) AS main_location_id,
    count(DISTINCT a.location_id) AS locations, count(*) AS active_days, sum(a.approvals) AS approvals,
    sum(a.approved_amount) AS approved_amount, sum(a.self_approved) AS self_approved_uses,
    sum(d.gross_known_subtotal) AS store_gross_on_active_days
  FROM approvals a JOIN applebees_semantic.gold.location_day d USING (location_id, business_date)
  GROUP BY a.manager_id
), emp AS (
  SELECT manager_id, count(DISTINCT discount_employee_id) AS employees_approved
  FROM applebees_semantic.gold.discount_events WHERE manager_id <> 0 GROUP BY manager_id
), rated AS (
  SELECT b.*, e.employees_approved,
    CAST(b.approved_amount / nullif(b.store_gross_on_active_days, 0) AS DOUBLE) AS approved_discount_rate,
    b.approvals >= 50 AS is_kpi_eligible
  FROM base b JOIN emp e USING (manager_id)
), fences AS (
  SELECT percentile_cont(0.25) WITHIN GROUP (ORDER BY approved_discount_rate) AS q1,
    percentile_cont(0.5) WITHIN GROUP (ORDER BY approved_discount_rate) AS median_rate,
    percentile_cont(0.75) WITHIN GROUP (ORDER BY approved_discount_rate) AS q3
  FROM rated WHERE is_kpi_eligible
)
SELECT r.manager_id, e.employee_name AS manager_name, r.main_location_id AS location_id, l.location_name,
  r.locations, r.active_days, r.approvals, r.employees_approved, r.approved_amount, r.self_approved_uses,
  r.store_gross_on_active_days, r.approved_discount_rate, r.is_kpi_eligible,
  f.median_rate AS peer_median_rate, f.q3 + 1.5 * (f.q3 - f.q1) AS outlier_threshold,
  r.is_kpi_eligible AND r.approved_discount_rate > f.q3 + 1.5 * (f.q3 - f.q1) AS is_outlier
FROM rated r CROSS JOIN fences f
LEFT JOIN applebees_semantic.silver.employees e ON e.employee_id = r.manager_id
LEFT JOIN applebees_semantic.silver.locations l ON l.location_id = r.main_location_id;

ALTER TABLE applebees_semantic.semantic.kpi_manager ALTER COLUMN manager_id COMMENT 'Manager employee ID. Primary key.';
ALTER TABLE applebees_semantic.semantic.kpi_manager ALTER COLUMN manager_name COMMENT 'Manager name. Personal data: show it only for watchlist or person-level questions.';
ALTER TABLE applebees_semantic.semantic.kpi_manager ALTER COLUMN location_id COMMENT 'Restaurant where the manager approved the most discounts.';
ALTER TABLE applebees_semantic.semantic.kpi_manager ALTER COLUMN location_name COMMENT 'Restaurant name where the manager approved the most discounts.';
ALTER TABLE applebees_semantic.semantic.kpi_manager ALTER COLUMN locations COMMENT 'Number of restaurants where the manager approved discounts.';
ALTER TABLE applebees_semantic.semantic.kpi_manager ALTER COLUMN active_days COMMENT 'Store-days where the manager approved at least one discount.';
ALTER TABLE applebees_semantic.semantic.kpi_manager ALTER COLUMN approvals COMMENT 'Discount applications approved by the manager.';
ALTER TABLE applebees_semantic.semantic.kpi_manager ALTER COLUMN employees_approved COMMENT 'Distinct employees whose discounts the manager approved.';
ALTER TABLE applebees_semantic.semantic.kpi_manager ALTER COLUMN approved_amount COMMENT 'Signed sum of the discounts the manager approved. Numerator of the manager discount rate.';
ALTER TABLE applebees_semantic.semantic.kpi_manager ALTER COLUMN self_approved_uses COMMENT 'Approvals where the manager also applied the discount (same ID in both roles).';
ALTER TABLE applebees_semantic.semantic.kpi_manager ALTER COLUMN store_gross_on_active_days COMMENT 'Gross sales of the restaurant on the days the manager approved discounts. Denominator of the manager discount rate (an approximation of the sales under that manager).';
ALTER TABLE applebees_semantic.semantic.kpi_manager ALTER COLUMN approved_discount_rate COMMENT 'Manager discount rate = approved_amount / store_gross_on_active_days.';
ALTER TABLE applebees_semantic.semantic.kpi_manager ALTER COLUMN is_kpi_eligible COMMENT 'True when the manager approved at least 50 discounts. Only eligible managers can be outliers.';
ALTER TABLE applebees_semantic.semantic.kpi_manager ALTER COLUMN peer_median_rate COMMENT 'Median approved discount rate of eligible managers (same value on every row).';
ALTER TABLE applebees_semantic.semantic.kpi_manager ALTER COLUMN outlier_threshold COMMENT 'Outlier cutoff Q3 + 1.5 x IQR of the eligible manager rates (same value on every row).';
ALTER TABLE applebees_semantic.semantic.kpi_manager ALTER COLUMN is_outlier COMMENT 'True when an eligible manager rate is above outlier_threshold. Signals risk, not proof of fraud.';

CREATE OR REPLACE TABLE applebees_semantic.semantic.kpi_location
COMMENT 'One row per restaurant with activity in the study period: official gold discount metrics, discount control indicators, voids and card tips, with an outlier flag on the discount rate (Q3 + 1.5 x IQR across restaurants). Synonyms: store KPIs, restaurant scorecard, sucursal.'
AS WITH day AS (
  SELECT location_id, count(*) AS active_days, sum(accepted_count) AS checks,
    sum(gross_known_subtotal) AS gross_sales, sum(discount_known_subtotal) AS discount_amount,
    sum(rate_discount_component) / nullif(sum(rate_gross_component), 0) AS discount_rate,
    sum(positive_check_count) / nullif(sum(discount_eligible_count), 0) AS discounted_check_frequency,
    sum(eligible_positive_amount) / nullif(sum(positive_check_count), 0) AS average_positive_discount
  FROM applebees_semantic.gold.location_day GROUP BY location_id
), people AS (
  SELECT location_id, count(DISTINCT nullif(manager_id, 0)) AS approving_managers,
    count(DISTINCT nullif(discount_employee_id, 0)) AS discounting_employees,
    count_if(manager_id = 0) AS unspecified_manager_uses,
    count_if(manager_id = discount_employee_id AND manager_id <> 0) AS self_approved_uses
  FROM applebees_semantic.gold.discount_events GROUP BY location_id
), v AS (
  SELECT location_id, count(*) AS voids, sum(amount) AS void_amount
  FROM applebees_semantic.silver.voids GROUP BY location_id
), t AS (
  SELECT location_id, sum(tip) / nullif(sum(amount - tip), 0) AS card_tip_rate
  FROM applebees_semantic.silver.payments WHERE is_credit_card GROUP BY location_id
), rated AS (
  SELECT d.*, p.approving_managers, p.discounting_employees, p.unspecified_manager_uses, p.self_approved_uses,
    coalesce(v.voids, 0) AS voids, coalesce(v.void_amount, 0) AS void_amount, t.card_tip_rate
  FROM day d LEFT JOIN people p USING (location_id) LEFT JOIN v USING (location_id) LEFT JOIN t USING (location_id)
), fences AS (
  SELECT percentile_cont(0.25) WITHIN GROUP (ORDER BY discount_rate) AS q1,
    percentile_cont(0.5) WITHIN GROUP (ORDER BY discount_rate) AS median_rate,
    percentile_cont(0.75) WITHIN GROUP (ORDER BY discount_rate) AS q3
  FROM rated
)
SELECT r.location_id, l.location_name, r.active_days, r.checks, r.gross_sales, r.discount_amount,
  CAST(r.discount_rate AS DOUBLE) AS discount_rate, CAST(r.discounted_check_frequency AS DOUBLE) AS discounted_check_frequency,
  CAST(r.average_positive_discount AS DECIMAL(38,2)) AS average_positive_discount,
  r.approving_managers, r.discounting_employees, r.unspecified_manager_uses, r.self_approved_uses,
  r.voids, r.void_amount, CAST(r.card_tip_rate AS DOUBLE) AS card_tip_rate,
  f.median_rate AS peer_median_rate, f.q3 + 1.5 * (f.q3 - f.q1) AS outlier_threshold,
  r.discount_rate > f.q3 + 1.5 * (f.q3 - f.q1) AS is_outlier
FROM rated r CROSS JOIN fences f
LEFT JOIN applebees_semantic.silver.locations l USING (location_id);

ALTER TABLE applebees_semantic.semantic.kpi_location ALTER COLUMN location_id COMMENT 'Restaurant ID. Primary key.';
ALTER TABLE applebees_semantic.semantic.kpi_location ALTER COLUMN location_name COMMENT 'Restaurant name.';
ALTER TABLE applebees_semantic.semantic.kpi_location ALTER COLUMN active_days COMMENT 'Business days with checks (of 115).';
ALTER TABLE applebees_semantic.semantic.kpi_location ALTER COLUMN checks COMMENT 'Accepted checks.';
ALTER TABLE applebees_semantic.semantic.kpi_location ALTER COLUMN gross_sales COMMENT 'Gross sales before discounts.';
ALTER TABLE applebees_semantic.semantic.kpi_location ALTER COLUMN discount_amount COMMENT 'Signed sum of all discounts.';
ALTER TABLE applebees_semantic.semantic.kpi_location ALTER COLUMN discount_rate COMMENT 'Official discount rate (gold-metrics-v1) = rate discount component / rate gross component.';
ALTER TABLE applebees_semantic.semantic.kpi_location ALTER COLUMN discounted_check_frequency COMMENT 'Share of discount-complete checks with at least one positive discount.';
ALTER TABLE applebees_semantic.semantic.kpi_location ALTER COLUMN average_positive_discount COMMENT 'Average positive discount per discounted check.';
ALTER TABLE applebees_semantic.semantic.kpi_location ALTER COLUMN approving_managers COMMENT 'Distinct managers who approved discounts. Few managers means weaker separation of duties.';
ALTER TABLE applebees_semantic.semantic.kpi_location ALTER COLUMN discounting_employees COMMENT 'Distinct employees who applied discounts.';
ALTER TABLE applebees_semantic.semantic.kpi_location ALTER COLUMN unspecified_manager_uses COMMENT 'Discounts with no approving manager recorded (manager ID 0).';
ALTER TABLE applebees_semantic.semantic.kpi_location ALTER COLUMN self_approved_uses COMMENT 'Discounts applied and approved by the same person.';
ALTER TABLE applebees_semantic.semantic.kpi_location ALTER COLUMN voids COMMENT 'Voided items.';
ALTER TABLE applebees_semantic.semantic.kpi_location ALTER COLUMN void_amount COMMENT 'Amount removed by voids.';
ALTER TABLE applebees_semantic.semantic.kpi_location ALTER COLUMN card_tip_rate COMMENT 'Card tips / card amount billed (tip excluded).';
ALTER TABLE applebees_semantic.semantic.kpi_location ALTER COLUMN peer_median_rate COMMENT 'Median store discount rate (same value on every row).';
ALTER TABLE applebees_semantic.semantic.kpi_location ALTER COLUMN outlier_threshold COMMENT 'Outlier cutoff Q3 + 1.5 x IQR of the store discount rates (same value on every row).';
ALTER TABLE applebees_semantic.semantic.kpi_location ALTER COLUMN is_outlier COMMENT 'True when the store discount rate is above outlier_threshold. Signals risk, not proof of fraud.';

ALTER TABLE applebees_semantic.semantic.kpi_employee ALTER COLUMN employee_id SET NOT NULL;
ALTER TABLE applebees_semantic.semantic.kpi_employee ADD CONSTRAINT kpi_employee_pk PRIMARY KEY (employee_id);
ALTER TABLE applebees_semantic.semantic.kpi_employee ADD CONSTRAINT kpi_employee_location_fk FOREIGN KEY (location_id) REFERENCES applebees_semantic.silver.locations;
ALTER TABLE applebees_semantic.semantic.kpi_manager ALTER COLUMN manager_id SET NOT NULL;
ALTER TABLE applebees_semantic.semantic.kpi_manager ADD CONSTRAINT kpi_manager_pk PRIMARY KEY (manager_id);
ALTER TABLE applebees_semantic.semantic.kpi_manager ADD CONSTRAINT kpi_manager_location_fk FOREIGN KEY (location_id) REFERENCES applebees_semantic.silver.locations;
ALTER TABLE applebees_semantic.semantic.kpi_location ALTER COLUMN location_id SET NOT NULL;
ALTER TABLE applebees_semantic.semantic.kpi_location ADD CONSTRAINT kpi_location_pk PRIMARY KEY (location_id);
ALTER TABLE applebees_semantic.semantic.kpi_location ADD CONSTRAINT kpi_location_location_fk FOREIGN KEY (location_id) REFERENCES applebees_semantic.silver.locations;

ALTER TABLE applebees_semantic.semantic.kpi_employee SET TAGS ('layer' = 'semantic', 'table_role' = 'kpi', 'grain' = 'employee', 'contains_pii' = 'true');
ALTER TABLE applebees_semantic.semantic.kpi_manager SET TAGS ('layer' = 'semantic', 'table_role' = 'kpi', 'grain' = 'manager', 'contains_pii' = 'true');
ALTER TABLE applebees_semantic.semantic.kpi_location SET TAGS ('layer' = 'semantic', 'table_role' = 'kpi', 'grain' = 'location');
