-- Keep the original signed double, occurrence identity, roles and all source provenance.
WITH converted AS (
  SELECT e.*,
    CASE WHEN amount BETWEEN -1.7976931348623157E308 AND 1.7976931348623157E308
      THEN try_cast(amount AS DECIMAL(28,6)) END AS amount_decimal
  FROM {{source_schema}}.silver_discount_events e
  WHERE generation_id = {{generation_id_literal}}
)
SELECT e.*,
  CASE WHEN e.amount IS NULL THEN 'MISSING'
    WHEN NOT (e.amount BETWEEN -1.7976931348623157E308 AND 1.7976931348623157E308) THEN 'NONFINITE'
    WHEN e.amount_decimal IS NULL THEN 'OUT_OF_RANGE'
    ELSE 'KNOWN' END AS amount_state,
  c.discount_complete
FROM converted e
JOIN {{storage_schema}}.gold_check_facts c
  ON e.location_id = c.location_id AND e.check_id = c.check_id
  AND e.business_date = c.business_date AND e.generation_id = c.generation_id
WHERE c.generation_id = {{generation_id_literal}}
