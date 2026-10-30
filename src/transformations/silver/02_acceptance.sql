-- Typed Silver contract (silver-payload-v1); deploy this checked-in SQL directly.
SET spark.sql.session.timeZone = UTC;
SET spark.sql.ansi.enabled = true;

-- Metadata and rescue evidence are excluded from the business hash; any rescue rejects K.
CREATE OR REFRESH PRIVATE MATERIALIZED VIEW signed_checks
AS SELECT *,
  to_json(struct(BusinessDate, CloseTime, Discounts, Id, ItemsSold, LocationId, LoyaltyId, OpenTime, Payments, RevenueCenterId, ServiceCharge, TableName, Tax, TrafficCount, Voids), map('ignoreNullFields','false')) AS canonical_payload,
  sha2(concat('silver-payload-v1:', to_json(struct(BusinessDate, CloseTime, Discounts, Id, ItemsSold, LocationId, LoyaltyId, OpenTime, Payments, RevenueCenterId, ServiceCharge, TableName, Tax, TrafficCount, Voids), map('ignoreNullFields','false'))), 256) AS payload_hash,
  'silver-payload-v1' AS payload_hash_version,
  try_cast(BusinessDate AS DATE) AS business_date,
  CAST(Id IS NULL OR LocationId IS NULL OR try_cast(BusinessDate AS DATE) IS NULL AS INT) AS invalid_key,
  CAST(_rescued_data IS NOT NULL AS INT) AS rescued,
  CAST(coalesce(exists(ItemsSold, x -> x.Sequence IS NULL), false)
    OR coalesce(size(array_distinct(transform(ItemsSold, x -> x.Sequence))) <> size(ItemsSold), false) AS INT) AS ambiguous_sequence
FROM raw_checks;

CREATE OR REFRESH PRIVATE MATERIALIZED VIEW check_decisions
AS SELECT LocationId, Id, business_date,
  count(DISTINCT payload_hash) AS versions,
  max(invalid_key) AS invalid_key, max(rescued) AS rescued, max(ambiguous_sequence) AS ambiguous_sequence,
  count(*) AS replay_count, sort_array(collect_set(_source_file)) AS source_files
FROM signed_checks GROUP BY LocationId, Id, business_date;

CREATE OR REFRESH PRIVATE MATERIALIZED VIEW accepted_checks
AS SELECT s.*, d.replay_count, d.source_files
FROM signed_checks s JOIN check_decisions d ON s.LocationId <=> d.LocationId AND s.Id <=> d.Id AND s.business_date <=> d.business_date
WHERE d.versions = 1 AND d.invalid_key = 0 AND d.rescued = 0 AND d.ambiguous_sequence = 0
QUALIFY row_number() OVER (PARTITION BY s.LocationId, s.Id, s.business_date
  ORDER BY s._source_file, s.payload_hash, s._ingested_at) = 1;

CREATE OR REFRESH MATERIALIZED VIEW silver_check_lineage
AS SELECT s.Id AS check_id, s.LocationId AS location_id, s.business_date, s.payload_hash, s.payload_hash_version,
  s._source_file, s._source_dt, s._ingested_at, count(*) AS occurrence_count,
  max(d.versions = 1 AND d.invalid_key = 0 AND d.rescued = 0 AND d.ambiguous_sequence = 0) AS accepted
FROM signed_checks s JOIN check_decisions d ON s.LocationId <=> d.LocationId AND s.Id <=> d.Id AND s.business_date <=> d.business_date
GROUP BY ALL;

CREATE OR REFRESH MATERIALIZED VIEW silver_check_review
AS SELECT s.Id AS check_id, s.LocationId AS location_id, s.business_date, s.payload_hash, s.payload_hash_version, s.canonical_payload,
  s._rescued_data, s._source_file, s._source_dt, min(s._ingested_at) AS _ingested_at,
  count(*) AS occurrence_count,
  sort_array(filter(array(
    CASE WHEN d.invalid_key = 1 THEN 'INVALID_KEY' END,
    CASE WHEN d.rescued = 1 THEN 'RESCUED_PAYLOAD' END,
    CASE WHEN d.ambiguous_sequence = 1 THEN 'AMBIGUOUS_SEQUENCE' END,
    CASE WHEN d.versions > 1 THEN 'CONFLICT' END), x -> x IS NOT NULL)) AS reason_codes
FROM signed_checks s JOIN check_decisions d ON s.LocationId <=> d.LocationId AND s.Id <=> d.Id AND s.business_date <=> d.business_date
WHERE d.invalid_key = 1 OR d.rescued = 1 OR d.ambiguous_sequence = 1 OR d.versions > 1
GROUP BY ALL;

CREATE OR REFRESH PRIVATE MATERIALIZED VIEW check_quality_versions
AS WITH counted AS (
  SELECT *, count(*) OVER (PARTITION BY LocationId, Id, business_date, payload_hash) AS exact_occurrences
  FROM signed_checks
)
SELECT s.LocationId AS location_id, s.Id AS check_id, s.business_date, s.payload_hash,
  s._source_dt, s.OpenTime, s.CloseTime, s.exact_occurrences,
  d.invalid_key, d.rescued, d.ambiguous_sequence, d.versions,
  min(named_struct('file',s._source_file,'ingested',s._ingested_at)) AS lineage
FROM counted s JOIN check_decisions d ON s.LocationId <=> d.LocationId AND s.Id <=> d.Id AND s.business_date <=> d.business_date
GROUP BY ALL;

