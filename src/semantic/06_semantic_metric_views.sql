-- Semantic layer, part 3: Unity Catalog metric views. Each one fixes the official definition of the measures
-- so Genie, dashboards and SQL compute them the same way. Query with MEASURE():
--   SELECT location_name, MEASURE(discount_rate) FROM applebees_semantic.semantic.mv_sales_discounts GROUP BY ALL
-- YAML spec version 1.1 (comments, display names and synonyms per field).

CREATE OR REPLACE VIEW applebees_semantic.semantic.mv_sales_discounts
WITH METRICS
LANGUAGE YAML
COMMENT 'Official sales and discount metrics (gold-metrics-v1) per check, sliceable by restaurant, date, channel and daypart. Use it for discount rate, gross sales, discounted check frequency and average discount questions.'
AS $$
version: 1.1
source: applebees_semantic.semantic.fct_check
joins:
  - name: loc
    source: applebees_semantic.semantic.dim_location
    on: source.location_id = loc.location_id
  - name: cal
    source: applebees_semantic.semantic.dim_date
    on: source.business_date = cal.business_date
  - name: rc
    source: applebees_semantic.semantic.dim_revenue_center
    on: source.revenue_center_id = rc.revenue_center_id
dimensions:
  - name: location_name
    expr: loc.location_name
    display_name: Restaurant
    comment: Restaurant (store) name.
    synonyms: [store, restaurant, location, branch, sucursal]
  - name: location_id
    expr: source.location_id
    display_name: Restaurant ID
    comment: Restaurant ID.
  - name: business_date
    expr: source.business_date
    display_name: Business date
    comment: Business date of the check.
    synonyms: [date, day, fecha]
  - name: week_start
    expr: cal.week_start
    display_name: Week
    comment: Monday of the week.
    synonyms: [week, semana]
  - name: month_name
    expr: cal.month_name
    display_name: Month
    comment: Month name.
    synonyms: [month, mes]
  - name: weekday_name
    expr: cal.weekday_name
    display_name: Weekday
    comment: Day of the week.
    synonyms: [day of week, dia de la semana]
  - name: is_weekend
    expr: cal.is_weekend
    display_name: Weekend
    comment: True on Friday, Saturday and Sunday.
  - name: revenue_center_name
    expr: rc.revenue_center_name
    display_name: Sales channel
    comment: Sales channel of the check (In-Store, To Go, delivery partners).
    synonyms: [channel, revenue center, order type, canal]
  - name: channel_group
    expr: rc.channel_group
    display_name: Channel group
    comment: Dine-in, Off-premise or Delivery partner.
  - name: daypart
    expr: source.daypart
    display_name: Daypart
    comment: Lunch (11-14h), Afternoon (14-17h), Dinner (17-21h), Late (21-02h) or Other, by check open time.
    synonyms: [shift, time of day, turno]
  - name: open_hour
    expr: source.open_hour
    display_name: Open hour
    comment: Hour the check was opened (0-23, restaurant clock).
    synonyms: [hour, hora]
  - name: rate_exclusion_reason
    expr: source.rate_exclusion_reason
    display_name: Rate exclusion reason
    comment: Why a check is left out of the discount rate (ZERO_GROSS and others). NULL when it counts.
measures:
  - name: check_count
    expr: COUNT(1)
    display_name: Checks
    comment: Number of accepted checks.
    synonyms: [checks, bills, tickets, transactions, cuentas]
  - name: guest_count
    expr: SUM(source.guest_count)
    display_name: Guests
    comment: Guests (covers) served.
    synonyms: [covers, traffic, guests, comensales]
  - name: gross_sales
    expr: SUM(source.gross_sales)
    display_name: Gross sales
    comment: Sales before discounts.
    synonyms: [sales, revenue, ventas]
    format:
      type: currency
      currency_code: USD
  - name: discount_amount
    expr: SUM(source.recorded_discount_amount)
    display_name: Discount amount
    comment: Signed total of all discounts (item and check level).
    synonyms: [discounts, discounted amount, descuentos]
    format:
      type: currency
      currency_code: USD
  - name: discount_rate
    expr: SUM(source.rate_discount_component) / NULLIF(SUM(source.rate_gross_component), 0)
    display_name: Discount rate
    comment: Official discount rate = discounts / gross sales of rate-eligible checks. Never average daily or store rates; always use this measure.
    synonyms: [discount percentage, discount ratio, tasa de descuento, porcentaje de descuento]
    format:
      type: percentage
  - name: discounted_check_count
    expr: COUNT_IF(source.discount_complete AND source.has_positive_discount)
    display_name: Discounted checks
    comment: Checks with at least one positive discount.
    synonyms: [checks with discount, cuentas con descuento]
  - name: discounted_check_frequency
    expr: COUNT_IF(source.discount_complete AND source.has_positive_discount) / NULLIF(COUNT_IF(source.discount_complete), 0)
    display_name: Discounted check frequency
    comment: Share of checks with at least one positive discount.
    synonyms: [discount frequency, share of discounted checks, frecuencia de descuento]
    format:
      type: percentage
  - name: average_positive_discount
    expr: SUM(source.eligible_positive_amount) / NULLIF(COUNT_IF(source.discount_complete AND source.has_positive_discount), 0)
    display_name: Average discount per discounted check
    comment: Average positive discount on checks that have one.
    synonyms: [average discount, descuento promedio]
    format:
      type: currency
      currency_code: USD
  - name: average_check
    expr: SUM(source.gross_sales) / NULLIF(COUNT(1), 0)
    display_name: Average check
    comment: Average gross sales per check.
    synonyms: [average ticket, ticket promedio]
    format:
      type: currency
      currency_code: USD
$$;

CREATE OR REPLACE VIEW applebees_semantic.semantic.mv_discount_usage
WITH METRICS
LANGUAGE YAML
COMMENT 'Discount applications by code, employee who applied them, approving manager, restaurant and date. Use it for who discounts, which codes, self-approvals and missing approvals.'
AS $$
version: 1.1
source: applebees_semantic.gold.discount_events
joins:
  - name: dsc
    source: applebees_semantic.semantic.dim_discount
    on: source.discount_id = dsc.discount_id
  - name: emp
    source: applebees_semantic.semantic.dim_employee
    on: source.discount_employee_id = emp.employee_id
  - name: mgr
    source: applebees_semantic.semantic.dim_employee
    on: source.manager_id = mgr.employee_id
  - name: loc
    source: applebees_semantic.semantic.dim_location
    on: source.location_id = loc.location_id
  - name: cal
    source: applebees_semantic.semantic.dim_date
    on: source.business_date = cal.business_date
dimensions:
  - name: discount_name
    expr: source.discount_name
    display_name: Discount code
    comment: Discount code as written in the POS.
    synonyms: [discount, discount type, code, promotion, comp, descuento]
  - name: discount_id
    expr: source.discount_id
    display_name: Discount ID
    comment: Discount code ID.
  - name: discount_level
    expr: source.discount_level
    display_name: Discount level
    comment: item (one line) or check (whole bill).
  - name: research_confidence
    expr: dsc.research_confidence
    display_name: Meaning confidence
    comment: Confirmed, Partial or Not found online (meaning of the code still to confirm with the client).
  - name: program_scope
    expr: dsc.program_scope
    display_name: Program scope
    comment: National, loyalty, franchise or restaurant-level program behind the code.
  - name: employee_name
    expr: emp.employee_name
    display_name: Employee
    comment: Employee who applied the discount.
    synonyms: [server, staff, applied by, empleado]
  - name: discount_employee_id
    expr: source.discount_employee_id
    display_name: Employee ID
    comment: ID of the employee who applied the discount. 0 means not specified.
  - name: manager_name
    expr: mgr.employee_name
    display_name: Approving manager
    comment: Manager who approved the discount.
    synonyms: [manager, approver, approved by, gerente]
  - name: manager_id
    expr: source.manager_id
    display_name: Manager ID
    comment: ID of the approving manager. 0 means no manager recorded.
  - name: is_self_approved
    expr: source.manager_id = source.discount_employee_id AND source.manager_id <> 0
    display_name: Self-approved
    comment: True when the same person applied and approved the discount.
  - name: location_name
    expr: loc.location_name
    display_name: Restaurant
    comment: Restaurant name.
    synonyms: [store, restaurant, location, sucursal]
  - name: business_date
    expr: source.business_date
    display_name: Business date
    comment: Business date of the check.
    synonyms: [date, fecha]
  - name: week_start
    expr: cal.week_start
    display_name: Week
    comment: Monday of the week.
  - name: month_name
    expr: cal.month_name
    display_name: Month
    comment: Month name.
  - name: weekday_name
    expr: cal.weekday_name
    display_name: Weekday
    comment: Day of the week.
measures:
  - name: discount_uses
    expr: COUNT(1)
    display_name: Discount uses
    comment: Number of discount applications.
    synonyms: [uses, applications, times used, usos]
  - name: discount_amount
    expr: SUM(source.amount)
    display_name: Discount amount
    comment: Signed sum of the discounts.
    synonyms: [discounted amount, money discounted, monto descontado]
    format:
      type: currency
      currency_code: USD
  - name: positive_discount_amount
    expr: SUM(CASE WHEN source.amount > 0 THEN source.amount ELSE 0 END)
    display_name: Positive discount amount
    comment: Sum of positive discounts only (reversals excluded). Basis of the discount type mix.
    format:
      type: currency
      currency_code: USD
  - name: average_discount
    expr: AVG(source.amount)
    display_name: Average discount per use
    comment: Average signed amount per discount application.
    format:
      type: currency
      currency_code: USD
  - name: discounted_checks
    expr: COUNT(DISTINCT source.location_id, source.business_date, source.check_id)
    display_name: Discounted checks
    comment: Distinct checks with at least one discount application.
  - name: discounting_employees
    expr: COUNT(DISTINCT NULLIF(source.discount_employee_id, 0))
    display_name: Employees applying discounts
    comment: Distinct employees who applied discounts.
  - name: approving_managers
    expr: COUNT(DISTINCT NULLIF(source.manager_id, 0))
    display_name: Approving managers
    comment: Distinct managers who approved discounts.
  - name: self_approved_uses
    expr: COUNT_IF(source.manager_id = source.discount_employee_id AND source.manager_id <> 0)
    display_name: Self-approved uses
    comment: Discounts applied and approved by the same person.
  - name: unapproved_uses
    expr: COUNT_IF(source.manager_id = 0)
    display_name: Uses without manager
    comment: Discounts with no approving manager recorded.
    synonyms: [missing approval, sin gerente]
$$;

CREATE OR REPLACE VIEW applebees_semantic.semantic.mv_card_tips
WITH METRICS
LANGUAGE YAML
COMMENT 'Tips on credit card payments by employee, restaurant and date. Cash tips are not recorded, so only card payments are included.'
AS $$
version: 1.1
source: applebees_semantic.silver.payments
filter: is_credit_card
joins:
  - name: emp
    source: applebees_semantic.semantic.dim_employee
    on: source.employee_id = emp.employee_id
  - name: loc
    source: applebees_semantic.semantic.dim_location
    on: source.location_id = loc.location_id
  - name: cal
    source: applebees_semantic.semantic.dim_date
    on: source.business_date = cal.business_date
dimensions:
  - name: employee_name
    expr: emp.employee_name
    display_name: Employee
    comment: Employee who took the payment (receives the tip).
    synonyms: [server, staff, empleado]
  - name: employee_id
    expr: source.employee_id
    display_name: Employee ID
    comment: Employee ID. 0 means not specified.
  - name: payment_type
    expr: source.payment_type
    display_name: Card type
    comment: VISA, MASTERCARD, AMEX, DISCOVER and others.
  - name: location_name
    expr: loc.location_name
    display_name: Restaurant
    comment: Restaurant name.
    synonyms: [store, restaurant, sucursal]
  - name: business_date
    expr: source.business_date
    display_name: Business date
    comment: Business date.
  - name: week_start
    expr: cal.week_start
    display_name: Week
    comment: Monday of the week.
  - name: weekday_name
    expr: cal.weekday_name
    display_name: Weekday
    comment: Day of the week.
measures:
  - name: card_payments
    expr: COUNT(1)
    display_name: Card payments
    comment: Number of credit card payments.
  - name: tip_amount
    expr: SUM(source.tip)
    display_name: Tips
    comment: Tips received on card payments.
    synonyms: [tips, gratuity, propinas]
    format:
      type: currency
      currency_code: USD
  - name: billed_amount
    expr: SUM(source.amount - source.tip)
    display_name: Amount billed
    comment: Card payment amount without the tip.
    format:
      type: currency
      currency_code: USD
  - name: tip_rate
    expr: SUM(source.tip) / NULLIF(SUM(source.amount - source.tip), 0)
    display_name: Tip rate
    comment: Tips / amount billed (tip excluded).
    synonyms: [tip percentage, porcentaje de propina]
    format:
      type: percentage
$$;

CREATE OR REPLACE VIEW applebees_semantic.semantic.mv_voids
WITH METRICS
LANGUAGE YAML
COMMENT 'Voided items (removed from a check after being ordered) by reason, employee, approving manager, item, restaurant and date.'
AS $$
version: 1.1
source: applebees_semantic.silver.voids
joins:
  - name: emp
    source: applebees_semantic.semantic.dim_employee
    on: source.employee_id = emp.employee_id
  - name: mgr
    source: applebees_semantic.semantic.dim_employee
    on: source.manager_id = mgr.employee_id
  - name: loc
    source: applebees_semantic.semantic.dim_location
    on: source.location_id = loc.location_id
  - name: cal
    source: applebees_semantic.semantic.dim_date
    on: source.business_date = cal.business_date
dimensions:
  - name: void_category
    expr: source.void_category
    display_name: Void reason
    comment: CUST CHANG, WRONG ITEM, NOT RECVD, TOO MANY, OTHER, 86'D ITEM, SERV ERR / SERVER ERR, WRONG CHK.
    synonyms: [reason, void type, motivo]
  - name: item_name
    expr: source.item_name
    display_name: Item
    comment: Voided menu item.
  - name: employee_name
    expr: emp.employee_name
    display_name: Employee
    comment: Employee who voided the item.
    synonyms: [server, staff, empleado]
  - name: manager_name
    expr: mgr.employee_name
    display_name: Approving manager
    comment: Manager who approved the void.
    synonyms: [manager, approver, gerente]
  - name: location_name
    expr: loc.location_name
    display_name: Restaurant
    comment: Restaurant name.
    synonyms: [store, restaurant, sucursal]
  - name: business_date
    expr: source.business_date
    display_name: Business date
    comment: Business date.
  - name: week_start
    expr: cal.week_start
    display_name: Week
    comment: Monday of the week.
measures:
  - name: void_count
    expr: COUNT(1)
    display_name: Voids
    comment: Number of voided items.
    synonyms: [voids, cancellations, cancelaciones]
  - name: void_amount
    expr: SUM(source.amount)
    display_name: Void amount
    comment: Amount removed by voids.
    format:
      type: currency
      currency_code: USD
  - name: void_quantity
    expr: SUM(source.quantity)
    display_name: Quantity voided
    comment: Units voided.
  - name: self_approved_voids
    expr: COUNT_IF(source.manager_id = source.employee_id AND source.manager_id <> 0)
    display_name: Self-approved voids
    comment: Voids made and approved by the same person.
$$;

ALTER VIEW applebees_semantic.semantic.mv_sales_discounts SET TAGS ('layer' = 'semantic', 'table_role' = 'metric_view');
ALTER VIEW applebees_semantic.semantic.mv_discount_usage SET TAGS ('layer' = 'semantic', 'table_role' = 'metric_view');
ALTER VIEW applebees_semantic.semantic.mv_card_tips SET TAGS ('layer' = 'semantic', 'table_role' = 'metric_view');
ALTER VIEW applebees_semantic.semantic.mv_voids SET TAGS ('layer' = 'semantic', 'table_role' = 'metric_view');
