-- Snapshot of production silver (${source_silver_schema}) with business documentation for Genie.
-- Re-run after the silver pipeline refreshes: CREATE OR REPLACE rewrites data, comments, keys and tags together.
-- Dropped on purpose: lineage columns (payload_hash*, _source_*, _ingested_at, source_files, replay_count),
-- audit tables with 0 rows (check_review, dimension_review), check_lineage, the item/check discount tables
-- (both are inside discount_events) and checks_test.
-- Amounts are in source currency units (USD assumed, not confirmed by the client).

-- ============================================================ dimensions

CREATE OR REPLACE TABLE ${catalog}.silver.locations
COMMENT 'Restaurant master: Applebee''s restaurants operated by Sun Holdings. Not every restaurant has checks in the study period.'
AS SELECT location_id, location_name, open_date, closed_date, time_zone
FROM ${source_silver_schema}.silver_locations;
ALTER TABLE ${catalog}.silver.locations ALTER COLUMN location_id COMMENT 'Restaurant ID. Primary key.';
ALTER TABLE ${catalog}.silver.locations ALTER COLUMN location_name COMMENT 'Restaurant name, usually the city or area.';
ALTER TABLE ${catalog}.silver.locations ALTER COLUMN open_date COMMENT 'Date the restaurant opened.';
ALTER TABLE ${catalog}.silver.locations ALTER COLUMN closed_date COMMENT 'Date the restaurant closed. NULL means it is still open.';
ALTER TABLE ${catalog}.silver.locations ALTER COLUMN time_zone COMMENT 'IANA time zone of the restaurant (for example America/Chicago).';

CREATE OR REPLACE TABLE ${catalog}.silver.revenue_centers
COMMENT 'Sales channels (POS revenue centers) a check or item line can belong to. 23 rows.'
AS SELECT revenue_center_id, revenue_center_name
FROM ${source_silver_schema}.silver_revenue_centers;
ALTER TABLE ${catalog}.silver.revenue_centers ALTER COLUMN revenue_center_id COMMENT 'Sales channel ID. Primary key.';
ALTER TABLE ${catalog}.silver.revenue_centers ALTER COLUMN revenue_center_name COMMENT 'Sales channel name: In-Store, To Go, Online, Catering, or a delivery partner such as Door Dash, Uber Eats or GRUBHUB.';

CREATE OR REPLACE TABLE ${catalog}.silver.employees
COMMENT 'Employee master, one row per employee ID. Date of birth, minor flag and hire date were left out on purpose (personal data; hire date is unreliable).'
AS SELECT employee_id, employee_name, location_id, home_location_id, is_borrowed, is_deleted,
  primary_job_id, job_ids
FROM ${source_silver_schema}.silver_employees;
ALTER TABLE ${catalog}.silver.employees ALTER COLUMN employee_id COMMENT 'Employee ID. Primary key. Referenced by item lines, payments, voids and discounts (as the employee who applied the discount or as the approving manager).';
ALTER TABLE ${catalog}.silver.employees ALTER COLUMN employee_name COMMENT 'Employee name as stored in the POS. Personal data: show only when the question is about a specific person.';
ALTER TABLE ${catalog}.silver.employees ALTER COLUMN location_id COMMENT 'Restaurant the employee record belongs to. Join to silver.locations.';
ALTER TABLE ${catalog}.silver.employees ALTER COLUMN home_location_id COMMENT 'Home restaurant ID from the employee master. Differs from location_id on most rows; use location_id for the store.';
ALTER TABLE ${catalog}.silver.employees ALTER COLUMN is_borrowed COMMENT 'True when the employee is borrowed from another restaurant.';
ALTER TABLE ${catalog}.silver.employees ALTER COLUMN is_deleted COMMENT 'True when the employee record is marked deleted (inactive) in the POS today. Most records are marked deleted, including people with activity in the period, so do not use it to filter transactions.';
ALTER TABLE ${catalog}.silver.employees ALTER COLUMN primary_job_id COMMENT 'Primary job code. Job names are not available; this code is the only proxy for role. There is no salary data.';
ALTER TABLE ${catalog}.silver.employees ALTER COLUMN job_ids COMMENT 'All job codes the employee can work.';

CREATE OR REPLACE TABLE ${catalog}.silver.items
COMMENT 'Menu item master.'
AS SELECT item_id, item_name, plu, sales_category_id, external_id
FROM ${source_silver_schema}.silver_items;
ALTER TABLE ${catalog}.silver.items ALTER COLUMN item_id COMMENT 'Menu item ID. Primary key.';
ALTER TABLE ${catalog}.silver.items ALTER COLUMN item_name COMMENT 'Menu item short name as printed by the POS (for example 2 FOR 25, BNLS WINGS 10).';
ALTER TABLE ${catalog}.silver.items ALTER COLUMN plu COMMENT 'Price look-up (PLU) code of the item.';
ALTER TABLE ${catalog}.silver.items ALTER COLUMN sales_category_id COMMENT 'Sales category code of the item. Category names are on the item lines (major_cat_name, sub_cat_name).';
ALTER TABLE ${catalog}.silver.items ALTER COLUMN external_id COMMENT 'Item ID in an external system.';

CREATE OR REPLACE TABLE ${catalog}.silver.discount_types
COMMENT 'The discount codes used in the study period. Their meaning, research status and documented restrictions are in reference.discount_dictionary.'
AS SELECT discount_id, trim(observed_names[0]) AS discount_name, observed_names
FROM ${source_silver_schema}.silver_discount_types;
ALTER TABLE ${catalog}.silver.discount_types ALTER COLUMN discount_id COMMENT 'Discount code ID. Primary key.';
ALTER TABLE ${catalog}.silver.discount_types ALTER COLUMN discount_name COMMENT 'Discount code name as written in the POS.';
ALTER TABLE ${catalog}.silver.discount_types ALTER COLUMN observed_names COMMENT 'Every name seen for this discount ID in the data (always one name in this period).';

-- ============================================================ transactions

CREATE OR REPLACE TABLE ${catalog}.silver.checks
COMMENT 'One row per accepted POS check (guest bill) in the study period. Key: (location_id, business_date, check_id). Only clean, single-version checks are included; rejected checks would be in the source review table.'
AS SELECT check_id, location_id, business_date, table_name, open_time, close_time, traffic_count,
  service_charge, loyalty_id, revenue_center_id, n_items, n_check_discounts, n_payments, n_voids
FROM ${source_silver_schema}.silver_checks;
ALTER TABLE ${catalog}.silver.checks ALTER COLUMN check_id COMMENT 'POS check number. Unique only together with location_id and business_date: the same number repeats across stores and days.';
ALTER TABLE ${catalog}.silver.checks ALTER COLUMN location_id COMMENT 'Restaurant ID. Join to silver.locations.';
ALTER TABLE ${catalog}.silver.checks ALTER COLUMN business_date COMMENT 'Business (accounting) date of the check. Use it for all date filters and for weekday analysis.';
ALTER TABLE ${catalog}.silver.checks ALTER COLUMN table_name COMMENT 'Table or order label recorded by the POS.';
ALTER TABLE ${catalog}.silver.checks ALTER COLUMN open_time COMMENT 'Time the check was opened, as recorded by the POS (restaurant clock time).';
ALTER TABLE ${catalog}.silver.checks ALTER COLUMN close_time COMMENT 'Time the check was closed (paid), as recorded by the POS.';
ALTER TABLE ${catalog}.silver.checks ALTER COLUMN traffic_count COMMENT 'Guest count (covers) on the check.';
ALTER TABLE ${catalog}.silver.checks ALTER COLUMN service_charge COMMENT 'Service charge on the check. Always 0 in this period.';
ALTER TABLE ${catalog}.silver.checks ALTER COLUMN loyalty_id COMMENT 'Club Applebee''s loyalty member ID. Empty on every check in this period.';
ALTER TABLE ${catalog}.silver.checks ALTER COLUMN revenue_center_id COMMENT 'Sales channel of the check. Join to silver.revenue_centers.';
ALTER TABLE ${catalog}.silver.checks ALTER COLUMN n_items COMMENT 'Number of item lines on the check, modifiers included.';
ALTER TABLE ${catalog}.silver.checks ALTER COLUMN n_check_discounts COMMENT 'Number of check-level discounts on the check (item-level discounts are not counted here).';
ALTER TABLE ${catalog}.silver.checks ALTER COLUMN n_payments COMMENT 'Number of payments (tenders) on the check.';
ALTER TABLE ${catalog}.silver.checks ALTER COLUMN n_voids COMMENT 'Number of voided items on the check.';

CREATE OR REPLACE TABLE ${catalog}.silver.check_items
COMMENT 'One row per item line of every check, modifiers included. Key: (location_id, business_date, check_id, item_sequence). Use parent_sequence = 0 for main items only.'
AS SELECT check_id, location_id, business_date, item_sequence, parent_sequence, item_id, item_name, plu,
  major_cat_id, major_cat_name, sub_cat_id, sub_cat_name, quantity, gross_price, sold_price,
  employee_id, revenue_center_id, order_time, seat, pos_source_id, item_discount_amount
FROM ${source_silver_schema}.silver_check_items;
ALTER TABLE ${catalog}.silver.check_items ALTER COLUMN check_id COMMENT 'POS check number. Part of the check key (location_id, business_date, check_id).';
ALTER TABLE ${catalog}.silver.check_items ALTER COLUMN location_id COMMENT 'Restaurant ID. Join to silver.locations.';
ALTER TABLE ${catalog}.silver.check_items ALTER COLUMN business_date COMMENT 'Business date of the check.';
ALTER TABLE ${catalog}.silver.check_items ALTER COLUMN item_sequence COMMENT 'Line number inside the check. With the check key it identifies the line; item-level discounts point to it.';
ALTER TABLE ${catalog}.silver.check_items ALTER COLUMN parent_sequence COMMENT 'item_sequence of the parent line. A value greater than 0 means this line is a modifier or add-on (side, sauce, temperature). About 55 percent of lines are modifiers.';
ALTER TABLE ${catalog}.silver.check_items ALTER COLUMN item_id COMMENT 'Menu item ID. Join to silver.items.';
ALTER TABLE ${catalog}.silver.check_items ALTER COLUMN item_name COMMENT 'Menu item short name as printed by the POS.';
ALTER TABLE ${catalog}.silver.check_items ALTER COLUMN plu COMMENT 'Price look-up (PLU) code of the item.';
ALTER TABLE ${catalog}.silver.check_items ALTER COLUMN major_cat_id COMMENT 'Major category ID of the item.';
ALTER TABLE ${catalog}.silver.check_items ALTER COLUMN major_cat_name COMMENT 'Major category name: FOOD, NA BEVERAGE, MISC, LIQUOR, DRAFT BEER, BTL BEER or WINE.';
ALTER TABLE ${catalog}.silver.check_items ALTER COLUMN sub_cat_id COMMENT 'Sub-category ID of the item.';
ALTER TABLE ${catalog}.silver.check_items ALTER COLUMN sub_cat_name COMMENT 'Sub-category name (for example APPETIZERS, STEAKS, SOFT DRNKS, SIDE CHC 1).';
ALTER TABLE ${catalog}.silver.check_items ALTER COLUMN quantity COMMENT 'Quantity ordered on the line.';
ALTER TABLE ${catalog}.silver.check_items ALTER COLUMN gross_price COMMENT 'Line total before discounts. It is already the total for the quantity: never multiply it by quantity. Sum of gross_price is gross sales.';
ALTER TABLE ${catalog}.silver.check_items ALTER COLUMN sold_price COMMENT 'Line amount after item-level discounts, as recorded by the POS.';
ALTER TABLE ${catalog}.silver.check_items ALTER COLUMN employee_id COMMENT 'Employee who rang in the line (usually the server). Join to silver.employees.';
ALTER TABLE ${catalog}.silver.check_items ALTER COLUMN revenue_center_id COMMENT 'Sales channel of the line. Join to silver.revenue_centers.';
ALTER TABLE ${catalog}.silver.check_items ALTER COLUMN order_time COMMENT 'Time the line was ordered, as recorded by the POS (restaurant clock time).';
ALTER TABLE ${catalog}.silver.check_items ALTER COLUMN seat COMMENT 'Seat number at the table.';
ALTER TABLE ${catalog}.silver.check_items ALTER COLUMN pos_source_id COMMENT 'POS source code of the line. Meaning not documented.';
ALTER TABLE ${catalog}.silver.check_items ALTER COLUMN item_discount_amount COMMENT 'Sum of item-level discounts on this line. Positive values reduce the price.';

CREATE OR REPLACE TABLE ${catalog}.silver.discount_events
COMMENT 'Every discount application, item and check level together. Main table for discount fraud analysis (who applied it, who approved it, which code).'
AS SELECT discount_level, location_id, check_id, business_date, item_sequence, discount_ordinal,
  discount_id, trim(discount_name) AS discount_name, amount, discount_employee_id, manager_id
FROM ${source_silver_schema}.silver_discount_events;
ALTER TABLE ${catalog}.silver.discount_events ALTER COLUMN discount_level COMMENT 'Where the discount was applied: item (one line) or check (whole bill).';
ALTER TABLE ${catalog}.silver.discount_events ALTER COLUMN location_id COMMENT 'Restaurant ID. Join to silver.locations.';
ALTER TABLE ${catalog}.silver.discount_events ALTER COLUMN check_id COMMENT 'POS check number. Part of the check key (location_id, business_date, check_id).';
ALTER TABLE ${catalog}.silver.discount_events ALTER COLUMN business_date COMMENT 'Business date of the check.';
ALTER TABLE ${catalog}.silver.discount_events ALTER COLUMN item_sequence COMMENT 'Discounted line (silver.check_items.item_sequence). NULL for check-level discounts.';
ALTER TABLE ${catalog}.silver.discount_events ALTER COLUMN discount_ordinal COMMENT 'Position of the discount within its line (item level) or within the check (check level).';
ALTER TABLE ${catalog}.silver.discount_events ALTER COLUMN discount_id COMMENT 'Discount code ID. Join to silver.discount_types and reference.discount_dictionary.';
ALTER TABLE ${catalog}.silver.discount_events ALTER COLUMN discount_name COMMENT 'Discount code name as written in the POS.';
ALTER TABLE ${catalog}.silver.discount_events ALTER COLUMN amount COMMENT 'Discount amount. Positive values are money taken off the bill; a few are negative (reversals).';
ALTER TABLE ${catalog}.silver.discount_events ALTER COLUMN discount_employee_id COMMENT 'Employee who applied the discount. Join to silver.employees.';
ALTER TABLE ${catalog}.silver.discount_events ALTER COLUMN manager_id COMMENT 'Manager who approved the discount. Join to silver.employees. Not specified on some check-level discounts (see silver.quality_issues).';

CREATE OR REPLACE TABLE ${catalog}.silver.payments
COMMENT 'One row per payment (tender) on a check. Key: (location_id, business_date, check_id, payment_ordinal). Use for tip analysis; restrict to card payments.'
AS SELECT check_id, location_id, business_date, payment_ordinal, employee_id, amount, gratuity_raw, tip,
  payment_type, payment_cat_no, is_credit_card, is_cash, is_gift_card, is_gift_cert, is_non_pos,
  is_petty_cash, payment_category_id, pos_source_id
FROM ${source_silver_schema}.silver_payments;
ALTER TABLE ${catalog}.silver.payments ALTER COLUMN check_id COMMENT 'POS check number. Part of the check key (location_id, business_date, check_id).';
ALTER TABLE ${catalog}.silver.payments ALTER COLUMN location_id COMMENT 'Restaurant ID. Join to silver.locations.';
ALTER TABLE ${catalog}.silver.payments ALTER COLUMN business_date COMMENT 'Business date of the check.';
ALTER TABLE ${catalog}.silver.payments ALTER COLUMN payment_ordinal COMMENT 'Position of the payment within the check.';
ALTER TABLE ${catalog}.silver.payments ALTER COLUMN employee_id COMMENT 'Employee who took the payment (usually the server who receives the tip). Join to silver.employees.';
ALTER TABLE ${catalog}.silver.payments ALTER COLUMN amount COMMENT 'Amount paid with this tender.';
ALTER TABLE ${catalog}.silver.payments ALTER COLUMN gratuity_raw COMMENT 'Tip exactly as stored by the POS: a negative number. Use tip instead.';
ALTER TABLE ${catalog}.silver.payments ALTER COLUMN tip COMMENT 'Tip amount (= -gratuity_raw). Reliable only for card payments: cash tips are not recorded.';
ALTER TABLE ${catalog}.silver.payments ALTER COLUMN payment_type COMMENT 'Tender name: VISA, MASTERCARD, AMEX, DISCOVER, CASH, GIFT CARD, or a delivery partner such as DOORDASH, UBEREATS, GRUBHUB.';
ALTER TABLE ${catalog}.silver.payments ALTER COLUMN payment_cat_no COMMENT 'Payment category number in the POS.';
ALTER TABLE ${catalog}.silver.payments ALTER COLUMN is_credit_card COMMENT 'True for credit card tenders.';
ALTER TABLE ${catalog}.silver.payments ALTER COLUMN is_cash COMMENT 'True for cash or debit tenders.';
ALTER TABLE ${catalog}.silver.payments ALTER COLUMN is_gift_card COMMENT 'True for gift card tenders.';
ALTER TABLE ${catalog}.silver.payments ALTER COLUMN is_gift_cert COMMENT 'True for gift certificate tenders.';
ALTER TABLE ${catalog}.silver.payments ALTER COLUMN is_non_pos COMMENT 'True for tenders recorded outside the POS.';
ALTER TABLE ${catalog}.silver.payments ALTER COLUMN is_petty_cash COMMENT 'True for petty cash entries.';
ALTER TABLE ${catalog}.silver.payments ALTER COLUMN payment_category_id COMMENT 'Payment category ID in the POS.';
ALTER TABLE ${catalog}.silver.payments ALTER COLUMN pos_source_id COMMENT 'POS source code of the payment. Meaning not documented.';

CREATE OR REPLACE TABLE ${catalog}.silver.voids
COMMENT 'One row per voided item (removed from a check after being ordered). Key: (location_id, business_date, check_id, void_ordinal).'
AS SELECT check_id, location_id, business_date, void_ordinal, employee_id, manager_id, item_id, item_name,
  plu, quantity, amount, void_category_id, void_category
FROM ${source_silver_schema}.silver_voids;
ALTER TABLE ${catalog}.silver.voids ALTER COLUMN check_id COMMENT 'POS check number. Part of the check key (location_id, business_date, check_id).';
ALTER TABLE ${catalog}.silver.voids ALTER COLUMN location_id COMMENT 'Restaurant ID. Join to silver.locations.';
ALTER TABLE ${catalog}.silver.voids ALTER COLUMN business_date COMMENT 'Business date of the check.';
ALTER TABLE ${catalog}.silver.voids ALTER COLUMN void_ordinal COMMENT 'Position of the void within the check.';
ALTER TABLE ${catalog}.silver.voids ALTER COLUMN employee_id COMMENT 'Employee who voided the item. Join to silver.employees.';
ALTER TABLE ${catalog}.silver.voids ALTER COLUMN manager_id COMMENT 'Manager who approved the void. Join to silver.employees.';
ALTER TABLE ${catalog}.silver.voids ALTER COLUMN item_id COMMENT 'Voided menu item. Join to silver.items.';
ALTER TABLE ${catalog}.silver.voids ALTER COLUMN item_name COMMENT 'Voided menu item short name.';
ALTER TABLE ${catalog}.silver.voids ALTER COLUMN plu COMMENT 'Price look-up (PLU) code of the voided item.';
ALTER TABLE ${catalog}.silver.voids ALTER COLUMN quantity COMMENT 'Quantity voided.';
ALTER TABLE ${catalog}.silver.voids ALTER COLUMN amount COMMENT 'Amount removed from the check by the void.';
ALTER TABLE ${catalog}.silver.voids ALTER COLUMN void_category_id COMMENT 'Void reason ID.';
ALTER TABLE ${catalog}.silver.voids ALTER COLUMN void_category COMMENT 'Void reason as written in the POS: CUST CHANG (customer changed mind), WRONG ITEM, NOT RECVD (not received), TOO MANY, OTHER, 86''D ITEM (out of stock), SERV ERR / SERVER ERR, WRONG CHK. Some reasons have two spellings.';

CREATE OR REPLACE TABLE ${catalog}.silver.taxes
COMMENT 'One row per tax line on a check. Key: (location_id, business_date, check_id, tax_ordinal).'
AS SELECT check_id, location_id, business_date, tax_ordinal, tax_category_id, tax_category, amount
FROM ${source_silver_schema}.silver_taxes;
ALTER TABLE ${catalog}.silver.taxes ALTER COLUMN check_id COMMENT 'POS check number. Part of the check key (location_id, business_date, check_id).';
ALTER TABLE ${catalog}.silver.taxes ALTER COLUMN location_id COMMENT 'Restaurant ID. Join to silver.locations.';
ALTER TABLE ${catalog}.silver.taxes ALTER COLUMN business_date COMMENT 'Business date of the check.';
ALTER TABLE ${catalog}.silver.taxes ALTER COLUMN tax_ordinal COMMENT 'Position of the tax line within the check.';
ALTER TABLE ${catalog}.silver.taxes ALTER COLUMN tax_category_id COMMENT 'Tax category ID.';
ALTER TABLE ${catalog}.silver.taxes ALTER COLUMN tax_category COMMENT 'Tax category name (Tax Category 1, Tax Category 2, Food Tax, Liquor Tax, Service Fee Tax, Delivery Fee Tax).';
ALTER TABLE ${catalog}.silver.taxes ALTER COLUMN amount COMMENT 'Tax amount charged.';

CREATE OR REPLACE TABLE ${catalog}.silver.quality_issues
COMMENT 'Rows flagged by the silver quality rules. Flagged rows are kept in the other tables, not removed. A quality flag is not evidence of fraud.'
AS SELECT issue_code, dataset_name, location_id, check_id, business_date, occurrence_key, reference_role,
  reference_id, observed_value, expected_value
FROM ${source_silver_schema}.silver_quality_issues;
ALTER TABLE ${catalog}.silver.quality_issues ALTER COLUMN issue_code COMMENT 'Quality rule that flagged the row: UNSPECIFIED_EMPLOYEE_ROLE (employee or manager not specified), NEGATIVE_PRICE, ACCOUNTING_DISCREPANCY (totals do not add up). Other rules exist but found nothing.';
ALTER TABLE ${catalog}.silver.quality_issues ALTER COLUMN dataset_name COMMENT 'Source silver table of the flagged row.';
ALTER TABLE ${catalog}.silver.quality_issues ALTER COLUMN location_id COMMENT 'Restaurant ID of the flagged check.';
ALTER TABLE ${catalog}.silver.quality_issues ALTER COLUMN check_id COMMENT 'POS check number of the flagged check.';
ALTER TABLE ${catalog}.silver.quality_issues ALTER COLUMN business_date COMMENT 'Business date of the flagged check.';
ALTER TABLE ${catalog}.silver.quality_issues ALTER COLUMN occurrence_key COMMENT 'Identifies the flagged row inside the check (for example the line or discount position).';
ALTER TABLE ${catalog}.silver.quality_issues ALTER COLUMN reference_role COMMENT 'Column or rule input that was checked (for example manager_id, sold_price, check_net).';
ALTER TABLE ${catalog}.silver.quality_issues ALTER COLUMN reference_id COMMENT 'ID value that was checked, when the rule is about a reference.';
ALTER TABLE ${catalog}.silver.quality_issues ALTER COLUMN observed_value COMMENT 'Value found in the data.';
ALTER TABLE ${catalog}.silver.quality_issues ALTER COLUMN expected_value COMMENT 'Value the rule expected.';

-- ============================================================ keys (informational, not enforced) and tags

ALTER TABLE ${catalog}.silver.locations ALTER COLUMN location_id SET NOT NULL;
ALTER TABLE ${catalog}.silver.locations ADD CONSTRAINT locations_pk PRIMARY KEY (location_id);
ALTER TABLE ${catalog}.silver.revenue_centers ALTER COLUMN revenue_center_id SET NOT NULL;
ALTER TABLE ${catalog}.silver.revenue_centers ADD CONSTRAINT revenue_centers_pk PRIMARY KEY (revenue_center_id);
ALTER TABLE ${catalog}.silver.employees ALTER COLUMN employee_id SET NOT NULL;
ALTER TABLE ${catalog}.silver.employees ADD CONSTRAINT employees_pk PRIMARY KEY (employee_id);
ALTER TABLE ${catalog}.silver.items ALTER COLUMN item_id SET NOT NULL;
ALTER TABLE ${catalog}.silver.items ADD CONSTRAINT items_pk PRIMARY KEY (item_id);
ALTER TABLE ${catalog}.silver.discount_types ALTER COLUMN discount_id SET NOT NULL;
ALTER TABLE ${catalog}.silver.discount_types ADD CONSTRAINT discount_types_pk PRIMARY KEY (discount_id);

ALTER TABLE ${catalog}.silver.checks ALTER COLUMN location_id SET NOT NULL;
ALTER TABLE ${catalog}.silver.checks ALTER COLUMN business_date SET NOT NULL;
ALTER TABLE ${catalog}.silver.checks ALTER COLUMN check_id SET NOT NULL;
ALTER TABLE ${catalog}.silver.checks ADD CONSTRAINT checks_pk PRIMARY KEY (location_id, business_date, check_id);
ALTER TABLE ${catalog}.silver.checks ADD CONSTRAINT checks_location_fk FOREIGN KEY (location_id) REFERENCES ${catalog}.silver.locations;
ALTER TABLE ${catalog}.silver.checks ADD CONSTRAINT checks_revenue_center_fk FOREIGN KEY (revenue_center_id) REFERENCES ${catalog}.silver.revenue_centers;

ALTER TABLE ${catalog}.silver.check_items ALTER COLUMN location_id SET NOT NULL;
ALTER TABLE ${catalog}.silver.check_items ALTER COLUMN business_date SET NOT NULL;
ALTER TABLE ${catalog}.silver.check_items ALTER COLUMN check_id SET NOT NULL;
ALTER TABLE ${catalog}.silver.check_items ALTER COLUMN item_sequence SET NOT NULL;
ALTER TABLE ${catalog}.silver.check_items ADD CONSTRAINT check_items_pk PRIMARY KEY (location_id, business_date, check_id, item_sequence);
ALTER TABLE ${catalog}.silver.check_items ADD CONSTRAINT check_items_check_fk FOREIGN KEY (location_id, business_date, check_id) REFERENCES ${catalog}.silver.checks;
ALTER TABLE ${catalog}.silver.check_items ADD CONSTRAINT check_items_item_fk FOREIGN KEY (item_id) REFERENCES ${catalog}.silver.items;
ALTER TABLE ${catalog}.silver.check_items ADD CONSTRAINT check_items_employee_fk FOREIGN KEY (employee_id) REFERENCES ${catalog}.silver.employees;
ALTER TABLE ${catalog}.silver.check_items ADD CONSTRAINT check_items_revenue_center_fk FOREIGN KEY (revenue_center_id) REFERENCES ${catalog}.silver.revenue_centers;

ALTER TABLE ${catalog}.silver.discount_events ADD CONSTRAINT discount_events_check_fk FOREIGN KEY (location_id, business_date, check_id) REFERENCES ${catalog}.silver.checks;
ALTER TABLE ${catalog}.silver.discount_events ADD CONSTRAINT discount_events_type_fk FOREIGN KEY (discount_id) REFERENCES ${catalog}.silver.discount_types;
ALTER TABLE ${catalog}.silver.discount_events ADD CONSTRAINT discount_events_employee_fk FOREIGN KEY (discount_employee_id) REFERENCES ${catalog}.silver.employees;
ALTER TABLE ${catalog}.silver.discount_events ADD CONSTRAINT discount_events_manager_fk FOREIGN KEY (manager_id) REFERENCES ${catalog}.silver.employees;

ALTER TABLE ${catalog}.silver.payments ALTER COLUMN location_id SET NOT NULL;
ALTER TABLE ${catalog}.silver.payments ALTER COLUMN business_date SET NOT NULL;
ALTER TABLE ${catalog}.silver.payments ALTER COLUMN check_id SET NOT NULL;
ALTER TABLE ${catalog}.silver.payments ALTER COLUMN payment_ordinal SET NOT NULL;
ALTER TABLE ${catalog}.silver.payments ADD CONSTRAINT payments_pk PRIMARY KEY (location_id, business_date, check_id, payment_ordinal);
ALTER TABLE ${catalog}.silver.payments ADD CONSTRAINT payments_check_fk FOREIGN KEY (location_id, business_date, check_id) REFERENCES ${catalog}.silver.checks;
ALTER TABLE ${catalog}.silver.payments ADD CONSTRAINT payments_employee_fk FOREIGN KEY (employee_id) REFERENCES ${catalog}.silver.employees;

ALTER TABLE ${catalog}.silver.voids ALTER COLUMN location_id SET NOT NULL;
ALTER TABLE ${catalog}.silver.voids ALTER COLUMN business_date SET NOT NULL;
ALTER TABLE ${catalog}.silver.voids ALTER COLUMN check_id SET NOT NULL;
ALTER TABLE ${catalog}.silver.voids ALTER COLUMN void_ordinal SET NOT NULL;
ALTER TABLE ${catalog}.silver.voids ADD CONSTRAINT voids_pk PRIMARY KEY (location_id, business_date, check_id, void_ordinal);
ALTER TABLE ${catalog}.silver.voids ADD CONSTRAINT voids_check_fk FOREIGN KEY (location_id, business_date, check_id) REFERENCES ${catalog}.silver.checks;
ALTER TABLE ${catalog}.silver.voids ADD CONSTRAINT voids_employee_fk FOREIGN KEY (employee_id) REFERENCES ${catalog}.silver.employees;
ALTER TABLE ${catalog}.silver.voids ADD CONSTRAINT voids_manager_fk FOREIGN KEY (manager_id) REFERENCES ${catalog}.silver.employees;
ALTER TABLE ${catalog}.silver.voids ADD CONSTRAINT voids_item_fk FOREIGN KEY (item_id) REFERENCES ${catalog}.silver.items;

ALTER TABLE ${catalog}.silver.taxes ALTER COLUMN location_id SET NOT NULL;
ALTER TABLE ${catalog}.silver.taxes ALTER COLUMN business_date SET NOT NULL;
ALTER TABLE ${catalog}.silver.taxes ALTER COLUMN check_id SET NOT NULL;
ALTER TABLE ${catalog}.silver.taxes ALTER COLUMN tax_ordinal SET NOT NULL;
ALTER TABLE ${catalog}.silver.taxes ADD CONSTRAINT taxes_pk PRIMARY KEY (location_id, business_date, check_id, tax_ordinal);
ALTER TABLE ${catalog}.silver.taxes ADD CONSTRAINT taxes_check_fk FOREIGN KEY (location_id, business_date, check_id) REFERENCES ${catalog}.silver.checks;

ALTER TABLE ${catalog}.silver.locations SET TAGS ('layer' = 'silver', 'table_role' = 'dimension');
ALTER TABLE ${catalog}.silver.revenue_centers SET TAGS ('layer' = 'silver', 'table_role' = 'dimension');
ALTER TABLE ${catalog}.silver.employees SET TAGS ('layer' = 'silver', 'table_role' = 'dimension', 'contains_pii' = 'true');
ALTER TABLE ${catalog}.silver.items SET TAGS ('layer' = 'silver', 'table_role' = 'dimension');
ALTER TABLE ${catalog}.silver.discount_types SET TAGS ('layer' = 'silver', 'table_role' = 'dimension');
ALTER TABLE ${catalog}.silver.checks SET TAGS ('layer' = 'silver', 'table_role' = 'fact', 'grain' = 'check');
ALTER TABLE ${catalog}.silver.check_items SET TAGS ('layer' = 'silver', 'table_role' = 'fact', 'grain' = 'item_line');
ALTER TABLE ${catalog}.silver.discount_events SET TAGS ('layer' = 'silver', 'table_role' = 'fact', 'grain' = 'discount_use');
ALTER TABLE ${catalog}.silver.payments SET TAGS ('layer' = 'silver', 'table_role' = 'fact', 'grain' = 'payment');
ALTER TABLE ${catalog}.silver.voids SET TAGS ('layer' = 'silver', 'table_role' = 'fact', 'grain' = 'void');
ALTER TABLE ${catalog}.silver.taxes SET TAGS ('layer' = 'silver', 'table_role' = 'fact', 'grain' = 'tax_line');
ALTER TABLE ${catalog}.silver.quality_issues SET TAGS ('layer' = 'silver', 'table_role' = 'audit');
ALTER TABLE ${catalog}.silver.employees ALTER COLUMN employee_name SET TAGS ('pii' = 'name');
