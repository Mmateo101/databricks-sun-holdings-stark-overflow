-- Typed Silver contract (silver-payload-v1); deploy this checked-in SQL directly.
SET spark.sql.session.timeZone = UTC;
SET spark.sql.ansi.enabled = true;

CREATE OR REFRESH MATERIALIZED VIEW silver_checks
AS SELECT
  Id AS check_id, LocationId AS location_id, c.business_date AS business_date,
  TableName AS table_name, try_to_timestamp(OpenTime) AS open_time, try_to_timestamp(CloseTime) AS close_time,
  TrafficCount AS traffic_count, ServiceCharge AS service_charge, LoyaltyId AS loyalty_id,
  RevenueCenterId AS revenue_center_id,
  size(ItemsSold) AS n_items, size(Discounts) AS n_check_discounts, size(Payments) AS n_payments, size(Voids) AS n_voids,
  c.payload_hash, c.payload_hash_version, c._source_file, c._source_dt, c._ingested_at, c.source_files, c.replay_count
FROM accepted_checks c;

CREATE OR REFRESH MATERIALIZED VIEW silver_check_items
AS SELECT
  c.Id AS check_id, c.LocationId AS location_id, c.business_date AS business_date,
  i.Sequence AS item_sequence, i.ParentSequence AS parent_sequence,
  i.ItemId AS item_id, i.ItemName AS item_name, i.ItemPLU AS plu,
  i.ItemMajorCatId AS major_cat_id, i.ItemMajorCatName AS major_cat_name,
  i.ItemSubCatId AS sub_cat_id, i.ItemSubCatName AS sub_cat_name,
  i.Quantity AS quantity, i.GrossPrice AS gross_price, i.SoldPrice AS sold_price,
  i.EmployeeId AS employee_id, i.RevenueCenterId AS revenue_center_id,
  try_to_timestamp(i.OrderTime) AS order_time, i.Seat AS seat, i.PosSourceId AS pos_source_id,
  aggregate(i.Discounts, CAST(0 AS DOUBLE), (acc, d) -> acc + d.Amount) AS item_discount_amount,
  c.payload_hash, c.payload_hash_version, c._source_file, c._source_dt, c._ingested_at, c.source_files, c.replay_count
FROM accepted_checks c LATERAL VIEW explode(c.ItemsSold) t AS i;

CREATE OR REFRESH MATERIALIZED VIEW silver_item_discounts
AS SELECT
  c.Id AS check_id, c.LocationId AS location_id, c.business_date AS business_date,
  i.Sequence AS item_sequence, i.ItemId AS item_id, i.EmployeeId AS item_employee_id,
  d.DiscountId AS discount_id, d.DiscountName AS discount_name, d.Amount AS amount,
  d.EmployeeId AS discount_employee_id, d.ManagerId AS manager_id, 'item' AS discount_level, ordinal AS discount_ordinal,
  c.payload_hash, c.payload_hash_version, c._source_file, c._source_dt, c._ingested_at, c.source_files, c.replay_count
FROM accepted_checks c
LATERAL VIEW explode(c.ItemsSold) t AS i
LATERAL VIEW posexplode(i.Discounts) t2 AS ordinal, d;

CREATE OR REFRESH MATERIALIZED VIEW silver_check_discounts
AS SELECT
  c.Id AS check_id, c.LocationId AS location_id, c.business_date AS business_date,
  d.DiscountId AS discount_id, d.DiscountName AS discount_name, d.Amount AS amount,
  d.EmployeeId AS discount_employee_id, d.ManagerId AS manager_id, 'check' AS discount_level, ordinal AS discount_ordinal,
  c.payload_hash, c.payload_hash_version, c._source_file, c._source_dt, c._ingested_at, c.source_files, c.replay_count
FROM accepted_checks c LATERAL VIEW posexplode(c.Discounts) t AS ordinal, d;

CREATE OR REFRESH MATERIALIZED VIEW silver_payments
AS SELECT
  c.Id AS check_id, c.LocationId AS location_id, c.business_date AS business_date,
  p.EmployeeId AS employee_id, p.Amount AS amount, p.Gratuity AS gratuity_raw, -p.Gratuity AS tip,
  p.PayCatName AS payment_type, p.PayCatNo AS payment_cat_no,
  p.IsCreditCard AS is_credit_card, p.IsCashDebit AS is_cash, p.IsGiftCard AS is_gift_card,
  p.IsGiftCert AS is_gift_cert, p.IsNonPOS AS is_non_pos, p.IsPettyCash AS is_petty_cash, p.PaymentCategoryId AS payment_category_id, p.PosSourceId AS pos_source_id, ordinal AS payment_ordinal,
  c.payload_hash, c.payload_hash_version, c._source_file, c._source_dt, c._ingested_at, c.source_files, c.replay_count
FROM accepted_checks c LATERAL VIEW posexplode(c.Payments) t AS ordinal, p;

CREATE OR REFRESH MATERIALIZED VIEW silver_voids
AS SELECT
  c.Id AS check_id, c.LocationId AS location_id, c.business_date AS business_date,
  v.EmployeeId AS employee_id, v.ManagerId AS manager_id, v.ItemId AS item_id, v.ItemName AS item_name,
  CAST(v.Quantity AS DOUBLE) AS quantity, v.Amount AS amount, v.VoidCategoryName AS void_category, v.ItemPLU AS plu, v.VoidCategoryId AS void_category_id, ordinal AS void_ordinal,
  c.payload_hash, c.payload_hash_version, c._source_file, c._source_dt, c._ingested_at, c.source_files, c.replay_count
FROM accepted_checks c LATERAL VIEW posexplode(c.Voids) t AS ordinal, v;

CREATE OR REFRESH MATERIALIZED VIEW silver_taxes
AS SELECT
  c.Id AS check_id, c.LocationId AS location_id, c.business_date AS business_date,
  x.TaxCategoryName AS tax_category, x.Amount AS amount, x.TaxCategoryId AS tax_category_id, ordinal AS tax_ordinal,
  c.payload_hash, c.payload_hash_version, c._source_file, c._source_dt, c._ingested_at, c.source_files, c.replay_count
FROM accepted_checks c LATERAL VIEW posexplode(c.Tax) t AS ordinal, x;

CREATE OR REFRESH MATERIALIZED VIEW silver_discount_events
AS SELECT discount_level, location_id, check_id, business_date, item_sequence, discount_ordinal, discount_id, discount_name, amount, discount_employee_id, manager_id, payload_hash, payload_hash_version, _source_file, _source_dt, _ingested_at, source_files, replay_count FROM silver_item_discounts
UNION ALL
SELECT discount_level, location_id, check_id, business_date, CAST(NULL AS BIGINT) AS item_sequence, discount_ordinal, discount_id, discount_name, amount, discount_employee_id, manager_id, payload_hash, payload_hash_version, _source_file, _source_dt, _ingested_at, source_files, replay_count FROM silver_check_discounts;

CREATE OR REFRESH MATERIALIZED VIEW silver_discount_types
AS SELECT discount_id, sort_array(collect_set(discount_name)) AS observed_names
FROM silver_discount_events GROUP BY discount_id;

