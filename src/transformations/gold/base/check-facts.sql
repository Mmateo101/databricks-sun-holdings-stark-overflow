-- source_schema is the retained generation-copy schema, never current Silver.
-- Execute under ANSI mode. Aggregate each child at K before joining accepted checks.
WITH items AS (
  SELECT location_id, check_id, business_date,
    CASE WHEN gross_price BETWEEN -1.7976931348623157E308 AND 1.7976931348623157E308
      THEN try_cast(gross_price AS DECIMAL(28,6)) END AS gross_decimal
  FROM {{source_schema}}.silver_check_items
  WHERE generation_id = {{generation_id_literal}}
), item_totals AS (
  SELECT location_id, check_id, business_date, count(*) AS sold_line_count,
    count(*) - count(gross_decimal) AS unknown_gross_count,
    coalesce(sum(CAST(coalesce(gross_decimal, 0) AS DECIMAL(38,6))),
      raise_error('Gold gross aggregation overflow')) AS gross_known_subtotal
  FROM items GROUP BY location_id, check_id, business_date
), events AS (
  SELECT location_id, check_id, business_date, discount_level,
    CASE WHEN amount BETWEEN -1.7976931348623157E308 AND 1.7976931348623157E308
      THEN try_cast(amount AS DECIMAL(28,6)) END AS amount_decimal
  FROM {{source_schema}}.silver_discount_events
  WHERE generation_id = {{generation_id_literal}}
), event_totals AS (
  SELECT location_id, check_id, business_date,
    count(*) AS application_count,
    count(*) - count(amount_decimal) AS unknown_discount_count,
    sum(CAST(discount_level = 'item' AS BIGINT)) AS item_application_count,
    sum(CAST(discount_level = 'check' AS BIGINT)) AS check_application_count,
    sum(CAST(coalesce(amount_decimal > 0, false) AS BIGINT)) AS positive_application_count,
    sum(CAST(coalesce(amount_decimal < 0, false) AS BIGINT)) AS negative_application_count,
    sum(CAST(coalesce(amount_decimal = 0, false) AS BIGINT)) AS zero_application_count,
    coalesce(sum(CAST(coalesce(amount_decimal, 0) AS DECIMAL(38,6))),
      raise_error('Gold discount aggregation overflow')) AS discount_known_subtotal,
    coalesce(sum(CAST(CASE WHEN amount_decimal > 0 THEN amount_decimal ELSE 0 END AS DECIMAL(38,6))),
      raise_error('Gold positive discount aggregation overflow')) AS positive_discount_known_subtotal,
    coalesce(sum(CAST(CASE WHEN amount_decimal < 0 THEN amount_decimal ELSE 0 END AS DECIMAL(38,6))),
      raise_error('Gold negative discount aggregation overflow')) AS negative_discount_known_subtotal,
    coalesce(sum(CAST(CASE WHEN discount_level = 'item' THEN coalesce(amount_decimal, 0) ELSE 0 END AS DECIMAL(38,6))),
      raise_error('Gold item discount aggregation overflow')) AS item_discount_known_subtotal,
    coalesce(sum(CAST(CASE WHEN discount_level = 'check' THEN coalesce(amount_decimal, 0) ELSE 0 END AS DECIMAL(38,6))),
      raise_error('Gold check discount aggregation overflow')) AS check_discount_known_subtotal
  FROM events GROUP BY location_id, check_id, business_date
), controls AS (
  SELECT c.location_id, c.check_id, c.business_date, c.generation_id,
    coalesce(i.sold_line_count, 0L) AS sold_line_count,
    coalesce(i.unknown_gross_count, 0L) AS unknown_gross_count,
    coalesce(e.application_count, 0L) AS application_count,
    coalesce(e.unknown_discount_count, 0L) AS unknown_discount_count,
    coalesce(e.item_application_count, 0L) AS item_application_count,
    coalesce(e.check_application_count, 0L) AS check_application_count,
    coalesce(e.positive_application_count, 0L) AS positive_application_count,
    coalesce(e.negative_application_count, 0L) AS negative_application_count,
    coalesce(e.zero_application_count, 0L) AS zero_application_count,
    coalesce(i.gross_known_subtotal, CAST(0 AS DECIMAL(38,6))) AS gross_known_subtotal,
    coalesce(e.discount_known_subtotal, CAST(0 AS DECIMAL(38,6))) AS discount_known_subtotal,
    coalesce(e.positive_discount_known_subtotal, CAST(0 AS DECIMAL(38,6))) AS positive_discount_known_subtotal,
    coalesce(e.negative_discount_known_subtotal, CAST(0 AS DECIMAL(38,6))) AS negative_discount_known_subtotal,
    coalesce(e.item_discount_known_subtotal, CAST(0 AS DECIMAL(38,6))) AS item_discount_known_subtotal,
    coalesce(e.check_discount_known_subtotal, CAST(0 AS DECIMAL(38,6))) AS check_discount_known_subtotal,
    c.payload_hash, c.payload_hash_version, c._source_file, c._source_dt,
    c._ingested_at, c.source_files, c.replay_count
  FROM {{source_schema}}.silver_checks c
  LEFT JOIN item_totals i USING (location_id, check_id, business_date)
  LEFT JOIN event_totals e USING (location_id, check_id, business_date)
  WHERE c.generation_id = {{generation_id_literal}}
), completeness AS (
  SELECT *, unknown_gross_count = 0 AS gross_complete,
    unknown_discount_count = 0 AS discount_complete,
    positive_application_count > 0 AS has_positive_discount
  FROM controls
), eligibility AS (
  SELECT *, gross_complete AND discount_complete AND gross_known_subtotal > 0 AS rate_eligible,
    CASE WHEN gross_complete THEN gross_known_subtotal END AS gross_sales,
    CASE WHEN discount_complete THEN discount_known_subtotal END AS recorded_discount_amount,
    CASE WHEN NOT gross_complete AND NOT discount_complete THEN 'INCOMPLETE_BOTH'
      WHEN NOT gross_complete THEN 'INCOMPLETE_GROSS'
      WHEN NOT discount_complete THEN 'INCOMPLETE_DISCOUNT'
      WHEN gross_known_subtotal = 0 THEN 'ZERO_GROSS'
      WHEN gross_known_subtotal < 0 THEN 'NEGATIVE_GROSS' END AS rate_exclusion_reason
  FROM completeness
)
SELECT *,
  CASE WHEN rate_eligible THEN gross_known_subtotal ELSE CAST(0 AS DECIMAL(38,6)) END AS rate_gross_component,
  CASE WHEN rate_eligible THEN discount_known_subtotal ELSE CAST(0 AS DECIMAL(38,6)) END AS rate_discount_component,
  CASE WHEN discount_complete THEN positive_discount_known_subtotal ELSE CAST(0 AS DECIMAL(38,6)) END AS eligible_positive_amount
FROM eligibility
