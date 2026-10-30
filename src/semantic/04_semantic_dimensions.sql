-- Semantic layer, part 1: clean dimensions and fact views that Genie and the metric views read.
-- Views only (no data copied). Employee and manager ID 0 means "not specified" in the POS.

CREATE OR REPLACE VIEW applebees_semantic.semantic.dim_location (
  location_id COMMENT 'Restaurant ID. Primary key.',
  location_name COMMENT 'Restaurant name, usually the city or area. Use it to answer questions by store or restaurant.',
  open_date COMMENT 'Date the restaurant opened.',
  closed_date COMMENT 'Date the restaurant closed. NULL when it is still open.',
  is_open COMMENT 'True when the restaurant has no closed date.',
  has_activity COMMENT 'True when the restaurant has checks in the study period. Filter on it to list only studied stores.',
  time_zone COMMENT 'IANA time zone of the restaurant.'
) COMMENT 'Restaurants (stores), with a flag for those with activity in the study period. Synonyms: store, restaurant, location, branch, sucursal.'
AS SELECT l.location_id, l.location_name, l.open_date, l.closed_date, l.closed_date IS NULL,
  EXISTS (SELECT 1 FROM applebees_semantic.gold.location_day d WHERE d.location_id = l.location_id),
  l.time_zone
FROM applebees_semantic.silver.locations l;

CREATE OR REPLACE VIEW applebees_semantic.semantic.dim_revenue_center (
  revenue_center_id COMMENT 'Sales channel ID. Primary key.',
  revenue_center_name COMMENT 'Sales channel name: In-Store, To Go, Online, Catering, or a delivery partner (Door Dash, Uber Eats, GRUBHUB, Amazon and others).',
  channel_group COMMENT 'Channel grouped in three: Dine-in (In-Store), Off-premise (To Go, Online, Catering, Olo) or Delivery partner (third-party delivery apps).'
) COMMENT 'Sales channels (POS revenue centers). Synonyms: channel, revenue center, order type.'
AS SELECT revenue_center_id, revenue_center_name,
  CASE WHEN revenue_center_name = 'In-Store' THEN 'Dine-in'
    WHEN revenue_center_name IN ('To Go', 'Online', 'Online AS', 'Catering') OR revenue_center_name LIKE 'Olo%' THEN 'Off-premise'
    ELSE 'Delivery partner' END
FROM applebees_semantic.silver.revenue_centers;

CREATE OR REPLACE VIEW applebees_semantic.semantic.dim_employee (
  employee_id COMMENT 'Employee ID. Primary key. ID 0 means not specified.',
  employee_name COMMENT 'Employee name. Personal data: show it only when the question is about specific people (for example a watchlist).',
  location_id COMMENT 'Restaurant of the employee record.',
  location_name COMMENT 'Restaurant name of the employee record.',
  primary_job_id COMMENT 'Primary job code, the only proxy for role (job names are not available).',
  is_borrowed COMMENT 'True when the employee is borrowed from another restaurant.'
) COMMENT 'Employees, including managers. The same table plays three roles: the server who rang a line, the employee who applied a discount, and the manager who approved a discount or void. Synonyms: staff, server, employee, empleado.'
AS SELECT e.employee_id, e.employee_name, e.location_id, l.location_name, e.primary_job_id, e.is_borrowed
FROM applebees_semantic.silver.employees e
LEFT JOIN applebees_semantic.silver.locations l ON l.location_id = e.location_id;

CREATE OR REPLACE VIEW applebees_semantic.semantic.dim_discount (
  discount_id COMMENT 'Discount code ID. Primary key.',
  discount_name COMMENT 'Discount code as written in the POS.',
  discount_level COMMENT 'Where the code is applied: item (one line) or check (whole bill). Each code is used at one level only.',
  web_meaning COMMENT 'What the code means according to web research. Says so when no definition was found.',
  research_confidence COMMENT 'Confidence of the meaning: Confirmed, Partial or Not found online. Not found online means the meaning must be confirmed with Sun Holdings.',
  research_status COMMENT 'Detailed research status from the discount dictionary (for example Partial - generic POS definition).',
  program_scope COMMENT 'Scope of the program behind the code (national, Club Applebee''s loyalty, franchise or restaurant level).',
  eligibility_documented COMMENT 'Who may use the offer according to sources. NULL when not documented.',
  minimum_spend_documented COMMENT 'Minimum spend required according to sources. NULL when not documented.',
  days_of_week_documented COMMENT 'Valid days of the week according to sources. NULL when not documented.',
  hours_documented COMMENT 'Valid hours according to sources. NULL when not documented.',
  channel_documented COMMENT 'Valid channel according to sources. NULL when not documented.',
  presence_pattern COMMENT 'When the code was used in the period (Entire period, Started or Ended mid-period, Limited window, Sporadic).'
) COMMENT 'The 106 discount codes with their meaning and documented restrictions from the team web research. Synonyms: discount type, discount code, promotion, comp, descuento.'
AS SELECT t.discount_id, t.discount_name, d.discount_level, d.web_meaning,
  CASE WHEN d.research_status LIKE 'Confirmed%' THEN 'Confirmed'
    WHEN d.research_status LIKE 'Partial%' THEN 'Partial'
    ELSE 'Not found online' END,
  d.research_status, d.program_scope, d.eligibility_documented, d.minimum_spend_documented,
  d.days_of_week_documented, d.hours_documented, d.channel_documented, d.presence_pattern
FROM applebees_semantic.silver.discount_types t
LEFT JOIN applebees_semantic.reference.discount_dictionary d ON d.discount_id = t.discount_id;

CREATE OR REPLACE VIEW applebees_semantic.semantic.dim_date (
  business_date COMMENT 'Business date. Primary key.',
  weekday_name COMMENT 'Day of the week name (Monday to Sunday).',
  weekday_number COMMENT 'Day of the week number, 1 = Monday to 7 = Sunday.',
  is_weekend COMMENT 'True on Friday, Saturday and Sunday (restaurant weekend).',
  week_start COMMENT 'Monday of the week of the business date.',
  month_start COMMENT 'First day of the month of the business date.',
  month_name COMMENT 'Month name (April to August 2026).',
  fraud_week_start COMMENT 'Thursday that starts the fraud week (Thursday to Wednesday), the week used by the fraud_employee_week and fraud_manager_week tables and the model.',
  is_partial_fraud_week COMMENT 'True for the first and last fraud weeks, which the study period cuts.'
) COMMENT 'Calendar of the study period. Two week definitions: week_start (Monday, used by the sales and discount dashboards) and fraud_week_start (Thursday, used by the fraud tables and the model).'
AS SELECT d, date_format(d, 'EEEE'), weekday(d) + 1,
  dayofweek(d) IN (1, 6, 7), date_trunc('WEEK', d)::DATE, date_trunc('MONTH', d)::DATE, date_format(d, 'MMMM'),
  date_sub(d, (dayofweek(d) + 2) % 7),
  date_sub(d, (dayofweek(d) + 2) % 7) < min(d) OVER () OR date_add(date_sub(d, (dayofweek(d) + 2) % 7), 6) > max(d) OVER ()
FROM (SELECT explode(sequence(min(business_date), max(business_date))) AS d FROM applebees_semantic.gold.location_day);

-- Fact views: gold facts plus the few silver columns the metric views need.

CREATE OR REPLACE VIEW applebees_semantic.semantic.fct_check (
  location_id COMMENT 'Restaurant ID.',
  business_date COMMENT 'Business date.',
  check_id COMMENT 'POS check number (unique with location_id and business_date).',
  revenue_center_id COMMENT 'Sales channel ID.',
  open_hour COMMENT 'Hour (0-23, restaurant clock) the check was opened.',
  daypart COMMENT 'Daypart of the check open time: Lunch (11-14h), Afternoon (14-17h), Dinner (17-21h), Late (21-02h), Other.',
  guest_count COMMENT 'Guests (covers) on the check.',
  gross_sales COMMENT 'Gross sales of the check before discounts. NULL when incomplete.',
  recorded_discount_amount COMMENT 'Signed total discount of the check. NULL when incomplete.',
  gross_complete COMMENT 'True when every line has a known gross price.',
  discount_complete COMMENT 'True when every discount has a known amount.',
  has_positive_discount COMMENT 'True when the check has at least one positive discount (a discounted check).',
  rate_eligible COMMENT 'True when the check counts for the discount rate.',
  rate_exclusion_reason COMMENT 'Why the check is left out of the discount rate (ZERO_GROSS and others). NULL when eligible.',
  rate_gross_component COMMENT 'Denominator piece of the discount rate.',
  rate_discount_component COMMENT 'Numerator piece of the discount rate.',
  eligible_positive_amount COMMENT 'Positive discounts of discount-complete checks.',
  item_discount_amount COMMENT 'Signed item-level discounts on the check.',
  check_discount_amount COMMENT 'Signed check-level discounts on the check.',
  discount_uses COMMENT 'Number of discount applications on the check.'
) COMMENT 'One row per check: gold check facts plus channel, open hour and guest count from silver.'
AS SELECT f.location_id, f.business_date, f.check_id, c.revenue_center_id, hour(c.open_time),
  CASE WHEN hour(c.open_time) BETWEEN 11 AND 13 THEN 'Lunch' WHEN hour(c.open_time) BETWEEN 14 AND 16 THEN 'Afternoon'
    WHEN hour(c.open_time) BETWEEN 17 AND 20 THEN 'Dinner' WHEN hour(c.open_time) >= 21 OR hour(c.open_time) <= 2 THEN 'Late'
    ELSE 'Other' END,
  c.traffic_count, f.gross_sales, f.recorded_discount_amount, f.gross_complete, f.discount_complete,
  f.has_positive_discount, f.rate_eligible, f.rate_exclusion_reason, f.rate_gross_component,
  f.rate_discount_component, f.eligible_positive_amount, f.item_discount_known_subtotal,
  f.check_discount_known_subtotal, f.application_count
FROM applebees_semantic.gold.check_facts f
JOIN applebees_semantic.silver.checks c USING (location_id, business_date, check_id);

ALTER VIEW applebees_semantic.semantic.dim_location SET TAGS ('layer' = 'semantic', 'table_role' = 'dimension');
ALTER VIEW applebees_semantic.semantic.dim_revenue_center SET TAGS ('layer' = 'semantic', 'table_role' = 'dimension');
ALTER VIEW applebees_semantic.semantic.dim_employee SET TAGS ('layer' = 'semantic', 'table_role' = 'dimension', 'contains_pii' = 'true');
ALTER VIEW applebees_semantic.semantic.dim_discount SET TAGS ('layer' = 'semantic', 'table_role' = 'dimension');
ALTER VIEW applebees_semantic.semantic.dim_date SET TAGS ('layer' = 'semantic', 'table_role' = 'dimension');
ALTER VIEW applebees_semantic.semantic.fct_check SET TAGS ('layer' = 'semantic', 'table_role' = 'fact', 'grain' = 'check');
