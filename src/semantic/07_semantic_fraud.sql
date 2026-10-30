-- Semantic layer for the fraud indicator tables (gold.fraud_employee_day/_week, gold.fraud_manager_day/_week).
-- Run after the fraud/*.sql builds and fraud/fraud_comments.sql (CREATE OR REPLACE drops keys and tags).
-- Keys are informational. Metric views read the DAY tables so dashboards can filter by date; the WEEK tables
-- are the model inputs and Genie reads them directly for exact weekly values.

ALTER TABLE applebees_semantic.gold.fraud_employee_day ALTER COLUMN business_date SET NOT NULL;
ALTER TABLE applebees_semantic.gold.fraud_employee_day ALTER COLUMN employee_id SET NOT NULL;
ALTER TABLE applebees_semantic.gold.fraud_employee_day ADD CONSTRAINT fraud_employee_day_pk PRIMARY KEY (business_date, employee_id);
ALTER TABLE applebees_semantic.gold.fraud_employee_day ADD CONSTRAINT fraud_employee_day_employee_fk FOREIGN KEY (employee_id) REFERENCES applebees_semantic.silver.employees;
ALTER TABLE applebees_semantic.gold.fraud_employee_day ADD CONSTRAINT fraud_employee_day_location_fk FOREIGN KEY (location_id) REFERENCES applebees_semantic.silver.locations;

ALTER TABLE applebees_semantic.gold.fraud_employee_week ALTER COLUMN week_start SET NOT NULL;
ALTER TABLE applebees_semantic.gold.fraud_employee_week ALTER COLUMN employee_id SET NOT NULL;
ALTER TABLE applebees_semantic.gold.fraud_employee_week ADD CONSTRAINT fraud_employee_week_pk PRIMARY KEY (week_start, employee_id);
ALTER TABLE applebees_semantic.gold.fraud_employee_week ADD CONSTRAINT fraud_employee_week_employee_fk FOREIGN KEY (employee_id) REFERENCES applebees_semantic.silver.employees;
ALTER TABLE applebees_semantic.gold.fraud_employee_week ADD CONSTRAINT fraud_employee_week_location_fk FOREIGN KEY (location_id) REFERENCES applebees_semantic.silver.locations;

ALTER TABLE applebees_semantic.gold.fraud_manager_day ALTER COLUMN business_date SET NOT NULL;
ALTER TABLE applebees_semantic.gold.fraud_manager_day ALTER COLUMN manager_id SET NOT NULL;
ALTER TABLE applebees_semantic.gold.fraud_manager_day ALTER COLUMN location_id SET NOT NULL;
ALTER TABLE applebees_semantic.gold.fraud_manager_day ADD CONSTRAINT fraud_manager_day_pk PRIMARY KEY (business_date, manager_id, location_id);
ALTER TABLE applebees_semantic.gold.fraud_manager_day ADD CONSTRAINT fraud_manager_day_manager_fk FOREIGN KEY (manager_id) REFERENCES applebees_semantic.silver.employees;
ALTER TABLE applebees_semantic.gold.fraud_manager_day ADD CONSTRAINT fraud_manager_day_location_fk FOREIGN KEY (location_id) REFERENCES applebees_semantic.silver.locations;

ALTER TABLE applebees_semantic.gold.fraud_manager_week ALTER COLUMN week_start SET NOT NULL;
ALTER TABLE applebees_semantic.gold.fraud_manager_week ALTER COLUMN manager_id SET NOT NULL;
ALTER TABLE applebees_semantic.gold.fraud_manager_week ALTER COLUMN location_id SET NOT NULL;
ALTER TABLE applebees_semantic.gold.fraud_manager_week ADD CONSTRAINT fraud_manager_week_pk PRIMARY KEY (week_start, manager_id, location_id);
ALTER TABLE applebees_semantic.gold.fraud_manager_week ADD CONSTRAINT fraud_manager_week_manager_fk FOREIGN KEY (manager_id) REFERENCES applebees_semantic.silver.employees;
ALTER TABLE applebees_semantic.gold.fraud_manager_week ADD CONSTRAINT fraud_manager_week_location_fk FOREIGN KEY (location_id) REFERENCES applebees_semantic.silver.locations;

ALTER TABLE applebees_semantic.gold.fraud_employee_day SET TAGS ('layer' = 'gold', 'table_role' = 'fraud_indicators', 'grain' = 'employee_day', 'contains_pii' = 'false');
ALTER TABLE applebees_semantic.gold.fraud_employee_week SET TAGS ('layer' = 'gold', 'table_role' = 'fraud_indicators', 'grain' = 'employee_week', 'week' = 'thursday_to_wednesday', 'use' = 'model_input');
ALTER TABLE applebees_semantic.gold.fraud_manager_day SET TAGS ('layer' = 'gold', 'table_role' = 'fraud_indicators', 'grain' = 'manager_location_day');
ALTER TABLE applebees_semantic.gold.fraud_manager_week SET TAGS ('layer' = 'gold', 'table_role' = 'fraud_indicators', 'grain' = 'manager_location_week', 'week' = 'thursday_to_wednesday', 'use' = 'model_input');

CREATE OR REPLACE VIEW applebees_semantic.semantic.mv_fraud_employee
WITH METRICS
LANGUAGE YAML
COMMENT 'Employee fraud indicators from gold.fraud_employee_day, sliceable by employee, restaurant, day and fraud week. Each check belongs to the employee who took its first payment. Ratios are recomputed from summed numerators and denominators. For exact weekly values per employee (model input) use gold.fraud_employee_week.'
AS $$
version: 1.1
source: applebees_semantic.gold.fraud_employee_day
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
    comment: Employee who owns the checks (took the first payment).
    synonyms: [server, staff, empleado, mesero]
  - name: employee_id
    expr: source.employee_id
    display_name: Employee ID
    comment: Employee ID.
  - name: location_name
    expr: loc.location_name
    display_name: Restaurant
    comment: Restaurant name.
    synonyms: [store, restaurant, location, sucursal]
  - name: business_date
    expr: source.business_date
    display_name: Business date
    comment: Business date.
    synonyms: [date, day, fecha]
  - name: fraud_week_start
    expr: cal.fraud_week_start
    display_name: Fraud week
    comment: Thursday that starts the fraud week (Thursday to Wednesday).
    synonyms: [week, semana]
  - name: is_partial_fraud_week
    expr: cal.is_partial_fraud_week
    display_name: Partial week
    comment: True for the first and last fraud weeks, cut by the study period.
  - name: month_name
    expr: cal.month_name
    display_name: Month
    comment: Month name.
  - name: weekday_name
    expr: cal.weekday_name
    display_name: Weekday
    comment: Day of the week.
measures:
  - name: employees
    expr: COUNT(DISTINCT source.employee_id)
    display_name: Employees
    comment: Distinct employees.
  - name: checks
    expr: SUM(source.checks)
    display_name: Checks
    comment: Checks owned by the employees.
  - name: sales
    expr: SUM(source.sales)
    display_name: Sales
    comment: Gross sales of the checks before discounts.
    format:
      type: currency
      currency_code: USD
  - name: discount_amount
    expr: SUM(source.discount_amount)
    display_name: Discount amount
    comment: Money discounted on the checks.
    format:
      type: currency
      currency_code: USD
  - name: discount_ratio
    expr: SUM(source.discount_amount) / NULLIF(SUM(source.sales), 0)
    display_name: Discount ratio
    comment: Indicator 1. Discount amount / sales. High is suspicious.
    synonyms: [discount rate, tasa de descuento]
    format:
      type: percentage
  - name: cash_ratio
    expr: (SUM(source.cash_or_no_tip_discounted_checks) / NULLIF(SUM(source.discounted_checks), 0)) / NULLIF(SUM(source.cash_or_no_tip_nondiscounted_checks) / NULLIF(SUM(source.nondiscounted_checks), 0), 0)
    display_name: Cash or no tip ratio
    comment: Indicator 2. Share of discounted checks paid only in cash or without tip, divided by the same share on checks without discount. Above 1 is suspicious.
    synonyms: [cash ratio, efectivo]
  - name: tip_ratio
    expr: (SUM(source.card_discounted_tips) / NULLIF(SUM(source.card_discounted_bill), 0)) / NULLIF(SUM(source.card_nondiscounted_tips) / NULLIF(SUM(source.card_nondiscounted_bill), 0), 0)
    display_name: Card tip ratio
    comment: Indicator 3. Card tip % on discounted checks (bill before discount) divided by card tip % on checks without discount. About 0.8 is normal; above 1 is suspicious (discount money moving into the tip).
    synonyms: [tip ratio, propina]
  - name: discount_frequency
    expr: SUM(source.discounted_checks) / NULLIF(SUM(source.checks), 0)
    display_name: Discount frequency
    comment: Indicator 4. Discounted checks / checks. High is suspicious.
    synonyms: [frecuencia de descuentos]
    format:
      type: percentage
  - name: full_comp_ratio
    expr: SUM(source.full_comp_checks) / NULLIF(SUM(source.checks), 0)
    display_name: Full comp ratio
    comment: Indicator 5. Checks discounted to zero / checks. High is suspicious.
    synonyms: [whole check given away, cuentas regaladas]
    format:
      type: percentage
  - name: discount_void_ratio
    expr: SUM(source.discount_void_checks) / NULLIF(SUM(source.checks), 0)
    display_name: Discount and void ratio
    comment: Indicator 6. Checks with a discount and a void / checks. High is suspicious.
    synonyms: [descuento y cancelacion]
    format:
      type: percentage
  - name: card_no_tip_ratio
    expr: (SUM(source.card_discounted_no_tip_checks) / NULLIF(SUM(source.card_discounted_checks), 0)) / NULLIF(SUM(source.card_nondiscounted_no_tip_checks) / NULLIF(SUM(source.card_nondiscounted_checks), 0), 0)
    display_name: Card no tip ratio
    comment: Indicator 7. Share of discounted card checks with tip 0, divided by the same share on card checks without discount. Above 1 is suspicious.
    synonyms: [tarjeta sin propina]
  - name: voids_per_100_checks
    expr: SUM(source.void_items) * 100.0 / NULLIF(SUM(source.checks), 0)
    display_name: Voids per 100 checks
    comment: Indicator 8a. Voided items per 100 checks. High is suspicious.
    synonyms: [cancelaciones]
  - name: void_ratio
    expr: SUM(source.void_amount) / NULLIF(SUM(source.sales), 0)
    display_name: Void ratio
    comment: Indicator 8b. Money voided / sales. High is suspicious.
    format:
      type: percentage
  - name: full_comp_checks
    expr: SUM(source.full_comp_checks)
    display_name: Full comp checks
    comment: Checks discounted to zero.
  - name: void_amount
    expr: SUM(source.void_amount)
    display_name: Void amount
    comment: Money removed by voids.
    format:
      type: currency
      currency_code: USD
$$;

CREATE OR REPLACE VIEW applebees_semantic.semantic.mv_fraud_manager
WITH METRICS
LANGUAGE YAML
COMMENT 'Manager fraud indicators from gold.fraud_manager_day, sliceable by manager, restaurant, day and fraud week. Group by manager: store_sales repeats for every manager of a store, so these measures do not describe a whole store (use mv_sales_discounts for that). Concentration and peer comparison are approval-weighted daily values; for exact weekly values (model input) use gold.fraud_manager_week.'
AS $$
version: 1.1
source: applebees_semantic.gold.fraud_manager_day
joins:
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
  - name: manager_name
    expr: mgr.employee_name
    display_name: Manager
    comment: Manager who approved discounts or voids.
    synonyms: [manager, approver, gerente]
  - name: manager_id
    expr: source.manager_id
    display_name: Manager ID
    comment: Manager ID.
  - name: location_name
    expr: loc.location_name
    display_name: Restaurant
    comment: Restaurant where the manager approved.
    synonyms: [store, restaurant, sucursal]
  - name: business_date
    expr: source.business_date
    display_name: Business date
    comment: Business date.
    synonyms: [date, fecha]
  - name: fraud_week_start
    expr: cal.fraud_week_start
    display_name: Fraud week
    comment: Thursday that starts the fraud week (Thursday to Wednesday).
    synonyms: [week, semana]
  - name: is_partial_fraud_week
    expr: cal.is_partial_fraud_week
    display_name: Partial week
    comment: True for the first and last fraud weeks, cut by the study period.
  - name: month_name
    expr: cal.month_name
    display_name: Month
    comment: Month name.
measures:
  - name: managers
    expr: COUNT(DISTINCT source.manager_id)
    display_name: Managers
    comment: Distinct managers.
  - name: approved_uses
    expr: SUM(source.approved_uses)
    display_name: Approvals
    comment: Discount applications approved.
  - name: approved_amount
    expr: SUM(source.approved_amount)
    display_name: Approved amount
    comment: Money of the discounts approved.
    format:
      type: currency
      currency_code: USD
  - name: approval_ratio
    expr: SUM(source.approved_amount) / NULLIF(SUM(source.store_sales), 0)
    display_name: Approval ratio
    comment: Indicator 1. Approved discount money / store sales on the manager's active days. High is suspicious. Valid when grouped by manager.
    synonyms: [approval rate, tasa de aprobacion]
    format:
      type: percentage
  - name: self_approved_uses
    expr: SUM(source.self_approved_uses)
    display_name: Self-approvals
    comment: Discounts the manager applied and approved.
    synonyms: [autoaprobaciones]
  - name: self_approval_ratio
    expr: SUM(source.self_approved_uses) / NULLIF(SUM(source.approved_uses), 0)
    display_name: Self-approval ratio
    comment: Indicator 2. Self-approvals / approvals. Above 0 is suspicious.
    format:
      type: percentage
  - name: concentration_ratio
    expr: SUM(source.top_employee_uses) / NULLIF(SUM(source.approved_uses), 0)
    display_name: Concentration ratio
    comment: Indicator 3. Share of approvals that went to the employee approved most each day (approval-weighted daily value). High is suspicious (possible collusion).
    synonyms: [concentracion]
    format:
      type: percentage
  - name: approved_voids
    expr: SUM(source.approved_voids)
    display_name: Approved voids
    comment: Voided items approved.
  - name: approved_voids_per_100_checks
    expr: SUM(source.approved_voids) * 100.0 / NULLIF(SUM(source.store_checks), 0)
    display_name: Approved voids per 100 checks
    comment: Indicator 4. Approved voids per 100 store checks on the manager's active days. High is suspicious.
    synonyms: [cancelaciones aprobadas]
  - name: approval_vs_peers
    expr: SUM(source.approved_amount) / NULLIF(SUM(source.store_approved_amount / NULLIF(source.store_managers, 0)), 0)
    display_name: Approval vs peers
    comment: Indicator 5. Approved money / average approved by the managers of the same store and day. 1 is average; well above 1 is suspicious.
    synonyms: [comparacion con pares]
$$;

ALTER VIEW applebees_semantic.semantic.mv_fraud_employee SET TAGS ('layer' = 'semantic', 'table_role' = 'metric_view');
ALTER VIEW applebees_semantic.semantic.mv_fraud_manager SET TAGS ('layer' = 'semantic', 'table_role' = 'metric_view');
