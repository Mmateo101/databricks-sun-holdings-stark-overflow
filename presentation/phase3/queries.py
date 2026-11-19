"""SQL used by the 'Pruebas estadisticas' notebook. Read-only, aggregates only."""

EMPLOYEE_TOTALS = """
SELECT employee_id,
       max_by(location_id, sales) AS location_id,
       count(*) AS weeks,
       sum(checks) AS checks, sum(sales) AS sales, sum(discount_amount) AS discount_amount,
       sum(discounted_checks) AS discounted_checks, sum(nondiscounted_checks) AS nondiscounted_checks,
       sum(cash_or_no_tip_discounted_checks) AS cnt_d, sum(cash_or_no_tip_nondiscounted_checks) AS cnt_n,
       sum(card_discounted_checks) AS card_d, sum(card_nondiscounted_checks) AS card_n,
       sum(card_discounted_tips) AS tips_d, sum(card_discounted_bill) AS bill_d,
       sum(card_nondiscounted_tips) AS tips_n, sum(card_nondiscounted_bill) AS bill_n,
       sum(card_discounted_no_tip_checks) AS notip_d, sum(card_nondiscounted_no_tip_checks) AS notip_n,
       sum(full_comp_checks) AS full_comp_checks, sum(discount_void_checks) AS discount_void_checks,
       sum(void_items) AS void_items, sum(void_amount) AS void_amount
FROM applebees_semantic.gold.fraud_employee_week
GROUP BY employee_id
"""

EMPLOYEE_WEEKS = """
SELECT week_start, employee_id, location_id, checks, sales, discount_amount,
       discounted_checks, nondiscounted_checks,
       cash_or_no_tip_discounted_checks AS cnt_d, cash_or_no_tip_nondiscounted_checks AS cnt_n,
       full_comp_checks, discount_void_checks, void_items
FROM applebees_semantic.gold.fraud_employee_week
"""

# Manager x restaurant over the whole period. Concentration and the cash share of approved
# discounted checks come straight from the discount events; denominators from fraud_manager_week.
MANAGER_TOTALS = """
WITH w AS (
  SELECT manager_id, location_id, count(*) AS weeks,
         sum(approved_uses) AS approved_uses, sum(approved_amount) AS approved_amount,
         sum(store_sales) AS store_sales, sum(store_checks) AS store_checks,
         sum(self_approved_uses) AS self_approved_uses, sum(approved_voids) AS approved_voids
  FROM applebees_semantic.gold.fraud_manager_week GROUP BY ALL),
ev AS (
  SELECT manager_id, location_id, discount_employee_id, business_date, check_id
  FROM applebees_semantic.silver.discount_events
  WHERE manager_id IS NOT NULL AND manager_id <> 0),
conc AS (
  SELECT manager_id, location_id, max(n) AS top_employee_uses, sum(n) AS uses, count(*) AS approved_employees
  FROM (SELECT manager_id, location_id, discount_employee_id, count(*) n FROM ev GROUP BY ALL) GROUP BY ALL),
pay AS (
  SELECT location_id, business_date, check_id,
         CASE WHEN bool_and(payment_type = 'CASH') OR sum(coalesce(tip,0)) = 0 THEN 1 ELSE 0 END AS cash_or_no_tip
  FROM applebees_semantic.silver.payments WHERE payment_type <> 'GC Sold' GROUP BY ALL),
mchk AS (SELECT DISTINCT manager_id, location_id, business_date, check_id FROM ev),
mcash AS (
  SELECT m.manager_id, m.location_id, count(*) AS approved_checks, sum(p.cash_or_no_tip) AS approved_cash_checks
  FROM mchk m JOIN pay p USING (location_id, business_date, check_id) GROUP BY ALL),
scash AS (
  SELECT d.location_id, count(*) AS store_disc_checks, sum(p.cash_or_no_tip) AS store_disc_cash_checks
  FROM (SELECT DISTINCT location_id, business_date, check_id FROM applebees_semantic.silver.discount_events) d
  JOIN pay p USING (location_id, business_date, check_id) GROUP BY ALL)
SELECT w.*, c.top_employee_uses, c.uses AS event_uses, c.approved_employees,
       m.approved_checks, m.approved_cash_checks, s.store_disc_checks, s.store_disc_cash_checks
FROM w JOIN conc c USING (manager_id, location_id)
       JOIN mcash m USING (manager_id, location_id)
       JOIN scash s USING (location_id)
"""

# Robustness: the cash-or-no-tip share counted only on PARTIAL discounts (discount < gross sales),
# because a fully comped check has no tip by construction. Same owner rule as the gold tables.
EMPLOYEE_WEEK_PARTIAL = """
WITH pay AS (
  SELECT location_id, business_date, check_id,
         min_by(employee_id, payment_ordinal) AS owner,
         CASE WHEN bool_and(payment_type = 'CASH') OR sum(coalesce(tip,0)) = 0 THEN 1 ELSE 0 END AS cash_or_no_tip
  FROM applebees_semantic.silver.payments WHERE payment_type <> 'GC Sold' GROUP BY ALL),
g AS (SELECT location_id, business_date, check_id, sum(gross_price) AS gross
      FROM applebees_semantic.silver.check_items GROUP BY ALL),
d AS (SELECT location_id, business_date, check_id, sum(amount) AS disc
      FROM applebees_semantic.silver.discount_events GROUP BY ALL)
SELECT date_sub(p.business_date, (dayofweek(p.business_date) + 2) % 7) AS week_start, p.owner AS employee_id,
       sum(CASE WHEN d.disc > 0 AND d.disc < g.gross THEN 1 ELSE 0 END) AS partial_checks,
       sum(CASE WHEN d.disc > 0 AND d.disc < g.gross THEN p.cash_or_no_tip ELSE 0 END) AS partial_cnt,
       sum(CASE WHEN d.disc IS NULL OR d.disc = 0 THEN 1 ELSE 0 END) AS nondisc_checks,
       sum(CASE WHEN d.disc IS NULL OR d.disc = 0 THEN p.cash_or_no_tip ELSE 0 END) AS nondisc_cnt
FROM pay p JOIN g USING (location_id, business_date, check_id)
LEFT JOIN d USING (location_id, business_date, check_id)
WHERE p.owner IS NOT NULL AND p.owner <> 0
GROUP BY ALL
"""
