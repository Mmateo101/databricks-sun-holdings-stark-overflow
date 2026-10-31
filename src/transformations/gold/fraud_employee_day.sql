-- ${catalog}.gold.fraud_employee_day: one row per employee and business date.
-- Indicators 1-3 designed by Mateo; indicators 4-8 added by Miguel.
-- Each check belongs to the employee who took its first payment (min_by(employee_id, payment_ordinal));
-- 'GC Sold' rows are gift card sales, not payments, and are left out. Checks with no payment or owner 0/NULL
-- have no owner and are dropped. Every ratio keeps its numerator and denominator as columns.
-- Card = is_credit_card OR payment_type LIKE 'OLO-%'. Payment amount includes the tip: billed = amount - tip.
-- ${target} is the table to write (the gold table, or a staging copy for validation).

CREATE OR REPLACE TABLE ${target} AS
WITH pay AS (  -- one row per check: owner, tender mix, tips, bills
  SELECT location_id, business_date, check_id,
    min_by(employee_id, payment_ordinal) AS owner,
    bool_and(payment_type = 'CASH') AS cash_only,
    sum(tip) AS tip,
    sum(amount - tip) AS billed,
    sum(CASE WHEN is_credit_card OR payment_type LIKE 'OLO-%' THEN tip ELSE 0 END) AS card_tip,
    sum(CASE WHEN is_credit_card OR payment_type LIKE 'OLO-%' THEN amount - tip ELSE 0 END) AS card_billed
  FROM ${catalog}.silver.payments
  WHERE payment_type <> 'GC Sold'
  GROUP BY location_id, business_date, check_id
),
items AS (
  SELECT location_id, business_date, check_id, sum(gross_price) AS sales
  FROM ${catalog}.silver.check_items
  GROUP BY location_id, business_date, check_id
),
disc AS (
  SELECT location_id, business_date, check_id, sum(amount) AS discount_amount
  FROM ${catalog}.gold.discount_events
  GROUP BY location_id, business_date, check_id
),
voids AS (
  SELECT location_id, business_date, check_id, count(*) AS void_items, sum(amount) AS void_amount
  FROM ${catalog}.silver.voids
  GROUP BY location_id, business_date, check_id
),
chk AS (  -- one row per owned check with every fact the indicators need
  SELECT p.location_id, p.business_date, p.check_id, p.owner AS employee_id,
    coalesce(i.sales, 0) AS sales,
    d.check_id IS NOT NULL AS is_discounted,
    coalesce(d.discount_amount, 0) AS discount_amount,
    p.cash_only, p.tip, p.billed, p.card_tip, p.card_billed,
    p.card_billed + coalesce(d.discount_amount, 0) * p.card_billed / nullif(p.billed, 0) AS card_bill_before_discount,
    coalesce(v.void_items, 0) AS void_items, coalesce(v.void_amount, 0) AS void_amount
  FROM pay p
  LEFT JOIN items i USING (location_id, business_date, check_id)
  LEFT JOIN disc d USING (location_id, business_date, check_id)
  LEFT JOIN voids v USING (location_id, business_date, check_id)
  WHERE p.owner IS NOT NULL AND p.owner <> 0
),
agg AS (
  SELECT business_date, employee_id, max(location_id) AS location_id,
    sum(sales) AS sales,
    sum(discount_amount) AS discount_amount,
    count_if(is_discounted) AS discounted_checks,
    count_if(NOT is_discounted) AS nondiscounted_checks,
    count_if(is_discounted AND card_billed > 0) AS card_discounted_checks,
    sum(CASE WHEN is_discounted AND card_billed > 0 THEN card_tip ELSE 0 END) AS card_discounted_tips,
    sum(CASE WHEN is_discounted AND card_billed > 0 THEN card_bill_before_discount ELSE 0 END) AS card_discounted_bill,
    count_if(NOT is_discounted AND card_billed > 0) AS card_nondiscounted_checks,
    sum(CASE WHEN NOT is_discounted AND card_billed > 0 THEN card_tip ELSE 0 END) AS card_nondiscounted_tips,
    sum(CASE WHEN NOT is_discounted AND card_billed > 0 THEN card_billed ELSE 0 END) AS card_nondiscounted_bill,
    count_if(is_discounted AND (cash_only OR coalesce(tip, 0) = 0)) AS cash_or_no_tip_discounted_checks,
    count_if(NOT is_discounted AND (cash_only OR coalesce(tip, 0) = 0)) AS cash_or_no_tip_nondiscounted_checks,
    -- new indicators (2026-10-29)
    count(*) AS checks,
    count_if(sales > 0 AND discount_amount >= sales) AS full_comp_checks,
    count_if(is_discounted AND void_items > 0) AS discount_void_checks,
    count_if(is_discounted AND card_billed > 0 AND card_tip = 0) AS card_discounted_no_tip_checks,
    count_if(NOT is_discounted AND card_billed > 0 AND card_tip = 0) AS card_nondiscounted_no_tip_checks,
    sum(void_items) AS void_items,
    sum(void_amount) AS void_amount
  FROM chk
  GROUP BY business_date, employee_id
)
SELECT business_date, employee_id, location_id, sales, discount_amount,
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
