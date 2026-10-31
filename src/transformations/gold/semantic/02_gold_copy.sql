-- Snapshot of the published gold generation (${source_gold_schema} views already filter it)
-- with business documentation for Genie. Metric definitions follow gold-metrics-v1 (gold reports/summary.sql).
-- ${generation_id} is filled by src/transformations/run_sql.py from ${source_gold_schema}.gold_publication (slot 1).
-- Amounts are DECIMAL in source currency units (USD assumed, not confirmed by the client).

CREATE OR REPLACE TABLE ${catalog}.gold.check_facts
COMMENT 'Gold fact table, one row per accepted check in the study period. Holds the components of the official discount metrics (gold-metrics-v1). Key: (location_id, business_date, check_id).'
AS SELECT location_id, check_id, business_date,
  sold_line_count, unknown_gross_count, application_count, unknown_discount_count,
  item_application_count, check_application_count,
  positive_application_count, negative_application_count, zero_application_count,
  gross_known_subtotal, discount_known_subtotal,
  positive_discount_known_subtotal, negative_discount_known_subtotal,
  item_discount_known_subtotal, check_discount_known_subtotal,
  gross_complete, discount_complete, has_positive_discount, rate_eligible,
  gross_sales, recorded_discount_amount, rate_exclusion_reason,
  rate_gross_component, rate_discount_component, eligible_positive_amount
FROM ${source_gold_schema}.gold_check_facts;
ALTER TABLE ${catalog}.gold.check_facts ALTER COLUMN location_id COMMENT 'Restaurant ID. Join to silver.locations.';
ALTER TABLE ${catalog}.gold.check_facts ALTER COLUMN check_id COMMENT 'POS check number. Part of the check key (location_id, business_date, check_id).';
ALTER TABLE ${catalog}.gold.check_facts ALTER COLUMN business_date COMMENT 'Business date of the check.';
ALTER TABLE ${catalog}.gold.check_facts ALTER COLUMN sold_line_count COMMENT 'Number of item lines on the check, modifiers included.';
ALTER TABLE ${catalog}.gold.check_facts ALTER COLUMN unknown_gross_count COMMENT 'Item lines whose gross price is missing or not a valid number. 0 on every check in this period.';
ALTER TABLE ${catalog}.gold.check_facts ALTER COLUMN application_count COMMENT 'Number of discount applications on the check, item and check level together.';
ALTER TABLE ${catalog}.gold.check_facts ALTER COLUMN unknown_discount_count COMMENT 'Discount applications whose amount is missing or not a valid number. 0 on every check in this period.';
ALTER TABLE ${catalog}.gold.check_facts ALTER COLUMN item_application_count COMMENT 'Number of item-level discount applications.';
ALTER TABLE ${catalog}.gold.check_facts ALTER COLUMN check_application_count COMMENT 'Number of check-level discount applications.';
ALTER TABLE ${catalog}.gold.check_facts ALTER COLUMN positive_application_count COMMENT 'Discount applications with a positive amount (money taken off).';
ALTER TABLE ${catalog}.gold.check_facts ALTER COLUMN negative_application_count COMMENT 'Discount applications with a negative amount (reversals).';
ALTER TABLE ${catalog}.gold.check_facts ALTER COLUMN zero_application_count COMMENT 'Discount applications with amount 0.';
ALTER TABLE ${catalog}.gold.check_facts ALTER COLUMN gross_known_subtotal COMMENT 'Sum of the known item line gross prices (gross sales before discounts).';
ALTER TABLE ${catalog}.gold.check_facts ALTER COLUMN discount_known_subtotal COMMENT 'Signed sum of the known discount amounts, both levels.';
ALTER TABLE ${catalog}.gold.check_facts ALTER COLUMN positive_discount_known_subtotal COMMENT 'Sum of the positive discount amounts.';
ALTER TABLE ${catalog}.gold.check_facts ALTER COLUMN negative_discount_known_subtotal COMMENT 'Sum of the negative discount amounts (reversals), a negative number.';
ALTER TABLE ${catalog}.gold.check_facts ALTER COLUMN item_discount_known_subtotal COMMENT 'Signed sum of item-level discounts.';
ALTER TABLE ${catalog}.gold.check_facts ALTER COLUMN check_discount_known_subtotal COMMENT 'Signed sum of check-level discounts.';
ALTER TABLE ${catalog}.gold.check_facts ALTER COLUMN gross_complete COMMENT 'True when every item line has a known gross price.';
ALTER TABLE ${catalog}.gold.check_facts ALTER COLUMN discount_complete COMMENT 'True when every discount on the check has a known amount.';
ALTER TABLE ${catalog}.gold.check_facts ALTER COLUMN has_positive_discount COMMENT 'True when the check has at least one positive discount. A discounted check.';
ALTER TABLE ${catalog}.gold.check_facts ALTER COLUMN rate_eligible COMMENT 'True when the check counts for the discount rate: gross and discounts complete and gross sales greater than 0.';
ALTER TABLE ${catalog}.gold.check_facts ALTER COLUMN gross_sales COMMENT 'Gross sales of the check (before discounts). NULL when gross_complete is false.';
ALTER TABLE ${catalog}.gold.check_facts ALTER COLUMN recorded_discount_amount COMMENT 'Total signed discount of the check. NULL when discount_complete is false.';
ALTER TABLE ${catalog}.gold.check_facts ALTER COLUMN rate_exclusion_reason COMMENT 'Why the check is left out of the discount rate: ZERO_GROSS, NEGATIVE_GROSS, INCOMPLETE_GROSS, INCOMPLETE_DISCOUNT or INCOMPLETE_BOTH. NULL when rate_eligible is true.';
ALTER TABLE ${catalog}.gold.check_facts ALTER COLUMN rate_gross_component COMMENT 'Gross sales when rate_eligible, else 0. Denominator of the discount rate: discount_rate = sum(rate_discount_component) / sum(rate_gross_component).';
ALTER TABLE ${catalog}.gold.check_facts ALTER COLUMN rate_discount_component COMMENT 'Signed discount when rate_eligible, else 0. Numerator of the discount rate.';
ALTER TABLE ${catalog}.gold.check_facts ALTER COLUMN eligible_positive_amount COMMENT 'Positive discount amount when discount_complete, else 0. Numerator of the average positive discount per discounted check.';

CREATE OR REPLACE TABLE ${catalog}.gold.discount_events
COMMENT 'Gold discount facts, one row per discount application. Same rows as silver.discount_events with a decimal amount and completeness flags. Use for discount type mix and for employee and manager discount analysis.'
AS SELECT discount_level, location_id, check_id, business_date, item_sequence, discount_ordinal,
  discount_id, trim(discount_name) AS discount_name, amount_decimal AS amount, amount_state,
  discount_employee_id, manager_id, discount_complete
FROM ${source_gold_schema}.gold_discount_events;
ALTER TABLE ${catalog}.gold.discount_events ALTER COLUMN discount_level COMMENT 'Where the discount was applied: item (one line) or check (whole bill).';
ALTER TABLE ${catalog}.gold.discount_events ALTER COLUMN location_id COMMENT 'Restaurant ID. Join to silver.locations.';
ALTER TABLE ${catalog}.gold.discount_events ALTER COLUMN check_id COMMENT 'POS check number. Part of the check key (location_id, business_date, check_id).';
ALTER TABLE ${catalog}.gold.discount_events ALTER COLUMN business_date COMMENT 'Business date of the check.';
ALTER TABLE ${catalog}.gold.discount_events ALTER COLUMN item_sequence COMMENT 'Discounted line (silver.check_items.item_sequence). NULL for check-level discounts.';
ALTER TABLE ${catalog}.gold.discount_events ALTER COLUMN discount_ordinal COMMENT 'Position of the discount within its line (item level) or within the check (check level).';
ALTER TABLE ${catalog}.gold.discount_events ALTER COLUMN discount_id COMMENT 'Discount code ID. Join to silver.discount_types and reference.discount_dictionary.';
ALTER TABLE ${catalog}.gold.discount_events ALTER COLUMN discount_name COMMENT 'Discount code name as written in the POS.';
ALTER TABLE ${catalog}.gold.discount_events ALTER COLUMN amount COMMENT 'Discount amount as DECIMAL(28,6). Positive values are money taken off; negative values are reversals.';
ALTER TABLE ${catalog}.gold.discount_events ALTER COLUMN amount_state COMMENT 'KNOWN when the amount is a valid number; MISSING, NONFINITE or OUT_OF_RANGE otherwise. All rows are KNOWN in this period.';
ALTER TABLE ${catalog}.gold.discount_events ALTER COLUMN discount_employee_id COMMENT 'Employee who applied the discount. Join to silver.employees.';
ALTER TABLE ${catalog}.gold.discount_events ALTER COLUMN manager_id COMMENT 'Manager who approved the discount. Join to silver.employees.';
ALTER TABLE ${catalog}.gold.discount_events ALTER COLUMN discount_complete COMMENT 'True when every discount on the same check has a known amount. Use only these rows for discount type mix.';

CREATE OR REPLACE TABLE ${catalog}.gold.location_day
COMMENT 'Gold daily summary, one row per restaurant and business date. Additive counts and amounts only: compute ratios after summing, never average daily ratios. discount_rate = sum(rate_discount_component) / sum(rate_gross_component); discounted_check_frequency = sum(positive_check_count) / sum(discount_eligible_count); average_positive_discount = sum(eligible_positive_amount) / sum(positive_check_count).'
AS SELECT * EXCEPT (generation_id)
FROM ${source_gold_schema}.gold_location_day;
ALTER TABLE ${catalog}.gold.location_day ALTER COLUMN location_id COMMENT 'Restaurant ID. Join to silver.locations.';
ALTER TABLE ${catalog}.gold.location_day ALTER COLUMN business_date COMMENT 'Business date.';
ALTER TABLE ${catalog}.gold.location_day ALTER COLUMN accepted_count COMMENT 'Number of accepted checks in the restaurant that day.';
ALTER TABLE ${catalog}.gold.location_day ALTER COLUMN gross_eligible_count COMMENT 'Checks with complete gross sales.';
ALTER TABLE ${catalog}.gold.location_day ALTER COLUMN discount_eligible_count COMMENT 'Checks with complete discounts. Denominator of the discounted check frequency.';
ALTER TABLE ${catalog}.gold.location_day ALTER COLUMN rate_eligible_count COMMENT 'Checks that count for the discount rate.';
ALTER TABLE ${catalog}.gold.location_day ALTER COLUMN positive_check_count COMMENT 'Discount-complete checks with at least one positive discount. Numerator of the discounted check frequency and denominator of the average positive discount.';
ALTER TABLE ${catalog}.gold.location_day ALTER COLUMN gross_incomplete_count COMMENT 'Checks with an unknown gross price on some line.';
ALTER TABLE ${catalog}.gold.location_day ALTER COLUMN discount_incomplete_count COMMENT 'Checks with an unknown discount amount.';
ALTER TABLE ${catalog}.gold.location_day ALTER COLUMN incomplete_both_count COMMENT 'Checks incomplete in both gross and discounts.';
ALTER TABLE ${catalog}.gold.location_day ALTER COLUMN zero_gross_count COMMENT 'Complete checks with gross sales equal to 0.';
ALTER TABLE ${catalog}.gold.location_day ALTER COLUMN negative_gross_count COMMENT 'Complete checks with negative gross sales.';
ALTER TABLE ${catalog}.gold.location_day ALTER COLUMN sold_line_count COMMENT 'Item lines sold, modifiers included.';
ALTER TABLE ${catalog}.gold.location_day ALTER COLUMN application_count COMMENT 'Discount applications, both levels.';
ALTER TABLE ${catalog}.gold.location_day ALTER COLUMN unknown_gross_count COMMENT 'Item lines with unknown gross price.';
ALTER TABLE ${catalog}.gold.location_day ALTER COLUMN unknown_discount_count COMMENT 'Discount applications with unknown amount.';
ALTER TABLE ${catalog}.gold.location_day ALTER COLUMN item_application_count COMMENT 'Item-level discount applications.';
ALTER TABLE ${catalog}.gold.location_day ALTER COLUMN check_application_count COMMENT 'Check-level discount applications.';
ALTER TABLE ${catalog}.gold.location_day ALTER COLUMN positive_application_count COMMENT 'Discount applications with a positive amount.';
ALTER TABLE ${catalog}.gold.location_day ALTER COLUMN negative_application_count COMMENT 'Discount applications with a negative amount.';
ALTER TABLE ${catalog}.gold.location_day ALTER COLUMN zero_application_count COMMENT 'Discount applications with amount 0.';
ALTER TABLE ${catalog}.gold.location_day ALTER COLUMN gross_known_subtotal COMMENT 'Gross sales from known line prices.';
ALTER TABLE ${catalog}.gold.location_day ALTER COLUMN discount_known_subtotal COMMENT 'Signed discounts from known amounts.';
ALTER TABLE ${catalog}.gold.location_day ALTER COLUMN positive_discount_known_subtotal COMMENT 'Positive discounts.';
ALTER TABLE ${catalog}.gold.location_day ALTER COLUMN negative_discount_known_subtotal COMMENT 'Negative discounts (reversals).';
ALTER TABLE ${catalog}.gold.location_day ALTER COLUMN item_discount_known_subtotal COMMENT 'Signed item-level discounts.';
ALTER TABLE ${catalog}.gold.location_day ALTER COLUMN check_discount_known_subtotal COMMENT 'Signed check-level discounts.';
ALTER TABLE ${catalog}.gold.location_day ALTER COLUMN rate_gross_component COMMENT 'Denominator of the discount rate (gross sales of rate-eligible checks).';
ALTER TABLE ${catalog}.gold.location_day ALTER COLUMN rate_discount_component COMMENT 'Numerator of the discount rate (signed discounts of rate-eligible checks).';
ALTER TABLE ${catalog}.gold.location_day ALTER COLUMN eligible_positive_amount COMMENT 'Positive discounts of discount-complete checks. Numerator of the average positive discount.';
ALTER TABLE ${catalog}.gold.location_day ALTER COLUMN gross_eligible_amount COMMENT 'Gross sales of gross-complete checks.';
ALTER TABLE ${catalog}.gold.location_day ALTER COLUMN discount_eligible_amount COMMENT 'Signed discounts of discount-complete checks.';

-- ============================================================ keys (informational), tags and traceability

ALTER TABLE ${catalog}.gold.check_facts ALTER COLUMN location_id SET NOT NULL;
ALTER TABLE ${catalog}.gold.check_facts ALTER COLUMN business_date SET NOT NULL;
ALTER TABLE ${catalog}.gold.check_facts ALTER COLUMN check_id SET NOT NULL;
ALTER TABLE ${catalog}.gold.check_facts ADD CONSTRAINT check_facts_pk PRIMARY KEY (location_id, business_date, check_id);
ALTER TABLE ${catalog}.gold.check_facts ADD CONSTRAINT check_facts_check_fk FOREIGN KEY (location_id, business_date, check_id) REFERENCES ${catalog}.silver.checks;
ALTER TABLE ${catalog}.gold.check_facts ADD CONSTRAINT check_facts_location_fk FOREIGN KEY (location_id) REFERENCES ${catalog}.silver.locations;

ALTER TABLE ${catalog}.gold.discount_events ADD CONSTRAINT gold_discount_events_check_fk FOREIGN KEY (location_id, business_date, check_id) REFERENCES ${catalog}.gold.check_facts;
ALTER TABLE ${catalog}.gold.discount_events ADD CONSTRAINT gold_discount_events_type_fk FOREIGN KEY (discount_id) REFERENCES ${catalog}.silver.discount_types;
ALTER TABLE ${catalog}.gold.discount_events ADD CONSTRAINT gold_discount_events_employee_fk FOREIGN KEY (discount_employee_id) REFERENCES ${catalog}.silver.employees;
ALTER TABLE ${catalog}.gold.discount_events ADD CONSTRAINT gold_discount_events_manager_fk FOREIGN KEY (manager_id) REFERENCES ${catalog}.silver.employees;

ALTER TABLE ${catalog}.gold.location_day ALTER COLUMN location_id SET NOT NULL;
ALTER TABLE ${catalog}.gold.location_day ALTER COLUMN business_date SET NOT NULL;
ALTER TABLE ${catalog}.gold.location_day ADD CONSTRAINT location_day_pk PRIMARY KEY (location_id, business_date);
ALTER TABLE ${catalog}.gold.location_day ADD CONSTRAINT location_day_location_fk FOREIGN KEY (location_id) REFERENCES ${catalog}.silver.locations;

ALTER TABLE ${catalog}.gold.check_facts SET TAGS ('layer' = 'gold', 'table_role' = 'fact', 'grain' = 'check', 'metrics_version' = 'gold-metrics-v1');
ALTER TABLE ${catalog}.gold.discount_events SET TAGS ('layer' = 'gold', 'table_role' = 'fact', 'grain' = 'discount_use', 'metrics_version' = 'gold-metrics-v1');
ALTER TABLE ${catalog}.gold.location_day SET TAGS ('layer' = 'gold', 'table_role' = 'fact', 'grain' = 'location_day', 'metrics_version' = 'gold-metrics-v1');

ALTER TABLE ${catalog}.gold.check_facts SET TBLPROPERTIES ('source.generation_id' = '${generation_id}');
ALTER TABLE ${catalog}.gold.discount_events SET TBLPROPERTIES ('source.generation_id' = '${generation_id}');
ALTER TABLE ${catalog}.gold.location_day SET TBLPROPERTIES ('source.generation_id' = '${generation_id}');
