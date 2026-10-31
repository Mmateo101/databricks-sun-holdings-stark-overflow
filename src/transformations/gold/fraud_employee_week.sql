-- ${catalog}.gold.fraud_employee_week: one row per employee and week (Thursday to Wednesday).
-- Indicators 1-3 designed by Mateo; indicators 4-8 added by Miguel.
-- Sums every count and money column of the day table, then recomputes the ratios from those sums
-- (daily ratios are never averaged). location_id = location with the most sales that week.
-- ${source} is the day table, ${target} the table to write. Run after fraud_employee_day.sql.

CREATE OR REPLACE TABLE ${target} AS
WITH d AS (
  SELECT *, date_sub(business_date, (dayofweek(business_date) + 2) % 7) AS week_start
  FROM ${source}
),
agg AS (
  SELECT week_start, employee_id,
    max_by(location_id, sales) AS location_id,
    count(DISTINCT business_date) AS days_worked,
    sum(sales) AS sales, sum(discount_amount) AS discount_amount,
    sum(discounted_checks) AS discounted_checks, sum(nondiscounted_checks) AS nondiscounted_checks,
    sum(card_discounted_checks) AS card_discounted_checks, sum(card_discounted_tips) AS card_discounted_tips,
    sum(card_discounted_bill) AS card_discounted_bill,
    sum(card_nondiscounted_checks) AS card_nondiscounted_checks, sum(card_nondiscounted_tips) AS card_nondiscounted_tips,
    sum(card_nondiscounted_bill) AS card_nondiscounted_bill,
    sum(cash_or_no_tip_discounted_checks) AS cash_or_no_tip_discounted_checks,
    sum(cash_or_no_tip_nondiscounted_checks) AS cash_or_no_tip_nondiscounted_checks,
    sum(checks) AS checks, sum(full_comp_checks) AS full_comp_checks,
    sum(discount_void_checks) AS discount_void_checks,
    sum(card_discounted_no_tip_checks) AS card_discounted_no_tip_checks,
    sum(card_nondiscounted_no_tip_checks) AS card_nondiscounted_no_tip_checks,
    sum(void_items) AS void_items, sum(void_amount) AS void_amount
  FROM d
  GROUP BY week_start, employee_id
)
SELECT week_start, employee_id, location_id, days_worked, sales, discount_amount,
  discount_amount / nullif(sales, 0) AS discount_ratio,
  discounted_checks, nondiscounted_checks,
  card_discounted_checks, card_discounted_tips, card_discounted_bill,
  card_nondiscounted_checks, card_nondiscounted_tips, card_nondiscounted_bill,
  (card_discounted_tips / nullif(card_discounted_bill, 0))
    / nullif(card_nondiscounted_tips / nullif(card_nondiscounted_bill, 0), 0) AS tip_ratio,
  cash_or_no_tip_discounted_checks, cash_or_no_tip_nondiscounted_checks,
  (cash_or_no_tip_discounted_checks / nullif(discounted_checks, 0))
    / nullif(cash_or_no_tip_nondiscounted_checks / nullif(nondiscounted_checks, 0), 0) AS cash_ratio,
  checks,
  discounted_checks / nullif(checks, 0) AS discount_frequency,
  full_comp_checks,
  full_comp_checks / nullif(checks, 0) AS full_comp_ratio,
  discount_void_checks,
  discount_void_checks / nullif(checks, 0) AS discount_void_ratio,
  card_discounted_no_tip_checks, card_nondiscounted_no_tip_checks,
  (card_discounted_no_tip_checks / nullif(card_discounted_checks, 0))
    / nullif(card_nondiscounted_no_tip_checks / nullif(card_nondiscounted_checks, 0), 0) AS card_no_tip_ratio,
  void_items, void_amount,
  void_items * 100.0 / nullif(checks, 0) AS voids_per_100_checks,
  void_amount / nullif(sales, 0) AS void_ratio
FROM agg;
