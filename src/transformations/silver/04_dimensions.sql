-- Typed Silver contract (silver-payload-v1); deploy this checked-in SQL directly.
SET spark.sql.session.timeZone = UTC;
SET spark.sql.ansi.enabled = true;

CREATE OR REFRESH PRIVATE MATERIALIZED VIEW signed_employees
AS SELECT *, to_json(struct(AlternateEmployeeId, Borrowed, DateOfBirth, Deleted, HireDate, HomeLocationId, Id, IsEmancipated, IsMinor, JobID, LocationEmployeeId, LocationId, Name, PayrollEmployeeId, PrimaryJobID), map('ignoreNullFields','false')) AS canonical_payload,
  sha2(to_json(struct(AlternateEmployeeId, Borrowed, DateOfBirth, Deleted, HireDate, HomeLocationId, Id, IsEmancipated, IsMinor, JobID, LocationEmployeeId, LocationId, Name, PayrollEmployeeId, PrimaryJobID), map('ignoreNullFields','false')), 256) AS payload_hash
FROM raw_employees;

CREATE OR REFRESH PRIVATE MATERIALIZED VIEW decisions_employees
AS SELECT Id, count(DISTINCT payload_hash) AS versions
FROM signed_employees GROUP BY Id;

CREATE OR REFRESH MATERIALIZED VIEW silver_employees
AS SELECT
  Id AS employee_id, Name AS employee_name, LocationId AS location_id, HomeLocationId AS home_location_id,
  to_date(HireDate) AS hire_date, to_date(DateOfBirth) AS date_of_birth,
  Borrowed AS is_borrowed, Deleted AS is_deleted, IsMinor AS is_minor,
  PrimaryJobID AS primary_job_id, JobID AS job_ids
FROM signed_employees
WHERE Id IS NOT NULL AND _rescued_data IS NULL
QUALIFY row_number() OVER (PARTITION BY Id ORDER BY payload_hash, _source_file, _ingested_at) = 1;

CREATE OR REFRESH PRIVATE MATERIALIZED VIEW signed_items
AS SELECT *, to_json(struct(ExternalId, Id, Name, Plu, SalesCategoryId), map('ignoreNullFields','false')) AS canonical_payload,
  sha2(to_json(struct(ExternalId, Id, Name, Plu, SalesCategoryId), map('ignoreNullFields','false')), 256) AS payload_hash
FROM raw_items;

CREATE OR REFRESH PRIVATE MATERIALIZED VIEW decisions_items
AS SELECT Id, count(DISTINCT payload_hash) AS versions
FROM signed_items GROUP BY Id;

CREATE OR REFRESH MATERIALIZED VIEW silver_items
AS SELECT Id AS item_id, Name AS item_name, Plu AS plu, SalesCategoryId AS sales_category_id, ExternalId AS external_id
FROM signed_items
WHERE Id IS NOT NULL AND _rescued_data IS NULL
QUALIFY row_number() OVER (PARTITION BY Id ORDER BY payload_hash, _source_file, _ingested_at) = 1;

CREATE OR REFRESH PRIVATE MATERIALIZED VIEW signed_locations
AS SELECT *, to_json(struct(ClosedDate, Id, Name, OpenDate, TimeZoneName), map('ignoreNullFields','false')) AS canonical_payload,
  sha2(to_json(struct(ClosedDate, Id, Name, OpenDate, TimeZoneName), map('ignoreNullFields','false')), 256) AS payload_hash
FROM raw_locations;

CREATE OR REFRESH PRIVATE MATERIALIZED VIEW decisions_locations
AS SELECT Id, count(DISTINCT payload_hash) AS versions
FROM signed_locations GROUP BY Id;

CREATE OR REFRESH MATERIALIZED VIEW silver_locations
AS SELECT
  Id AS location_id, Name AS location_name,
  to_date(OpenDate) AS open_date, to_date(ClosedDate) AS closed_date, TimeZoneName AS time_zone
FROM signed_locations
WHERE Id IS NOT NULL AND _rescued_data IS NULL
QUALIFY row_number() OVER (PARTITION BY Id ORDER BY payload_hash, _source_file, _ingested_at) = 1;

CREATE OR REFRESH PRIVATE MATERIALIZED VIEW signed_revenue_centers
AS SELECT *, to_json(struct(Id, Name), map('ignoreNullFields','false')) AS canonical_payload,
  sha2(to_json(struct(Id, Name), map('ignoreNullFields','false')), 256) AS payload_hash
FROM raw_revenue_centers;

CREATE OR REFRESH PRIVATE MATERIALIZED VIEW decisions_revenue_centers
AS SELECT Id, count(DISTINCT payload_hash) AS versions
FROM signed_revenue_centers GROUP BY Id;

CREATE OR REFRESH MATERIALIZED VIEW silver_revenue_centers
AS SELECT Id AS revenue_center_id, Name AS revenue_center_name FROM signed_revenue_centers
WHERE Id IS NOT NULL AND _rescued_data IS NULL
QUALIFY row_number() OVER (PARTITION BY Id ORDER BY payload_hash, _source_file, _ingested_at) = 1;

CREATE OR REFRESH MATERIALIZED VIEW silver_dimension_review
AS SELECT 'employees' AS dimension_name, s.Id AS dimension_id, s.payload_hash, s.canonical_payload,
  s._source_file, s._source_dt, min(s._ingested_at) AS _ingested_at,
  sort_array(filter(array(
    CASE WHEN d.versions > 1 THEN 'DIMENSION_AMBIGUITY' END,
    CASE WHEN s.Id IS NULL THEN 'INVALID_KEY' END,
    CASE WHEN s._rescued_data IS NOT NULL THEN 'RESCUED_PAYLOAD' END), x -> x IS NOT NULL)) AS reason_codes
FROM signed_employees s JOIN decisions_employees d ON s.Id <=> d.Id
WHERE d.versions > 1 OR s.Id IS NULL OR s._rescued_data IS NOT NULL
GROUP BY ALL
UNION ALL
SELECT 'items' AS dimension_name, s.Id AS dimension_id, s.payload_hash, s.canonical_payload,
  s._source_file, s._source_dt, min(s._ingested_at) AS _ingested_at,
  sort_array(filter(array(
    CASE WHEN d.versions > 1 THEN 'DIMENSION_AMBIGUITY' END,
    CASE WHEN s.Id IS NULL THEN 'INVALID_KEY' END,
    CASE WHEN s._rescued_data IS NOT NULL THEN 'RESCUED_PAYLOAD' END), x -> x IS NOT NULL)) AS reason_codes
FROM signed_items s JOIN decisions_items d ON s.Id <=> d.Id
WHERE d.versions > 1 OR s.Id IS NULL OR s._rescued_data IS NOT NULL
GROUP BY ALL
UNION ALL
SELECT 'locations' AS dimension_name, s.Id AS dimension_id, s.payload_hash, s.canonical_payload,
  s._source_file, s._source_dt, min(s._ingested_at) AS _ingested_at,
  sort_array(filter(array(
    CASE WHEN d.versions > 1 THEN 'DIMENSION_AMBIGUITY' END,
    CASE WHEN s.Id IS NULL THEN 'INVALID_KEY' END,
    CASE WHEN s._rescued_data IS NOT NULL THEN 'RESCUED_PAYLOAD' END), x -> x IS NOT NULL)) AS reason_codes
FROM signed_locations s JOIN decisions_locations d ON s.Id <=> d.Id
WHERE d.versions > 1 OR s.Id IS NULL OR s._rescued_data IS NOT NULL
GROUP BY ALL
UNION ALL
SELECT 'revenue_centers' AS dimension_name, s.Id AS dimension_id, s.payload_hash, s.canonical_payload,
  s._source_file, s._source_dt, min(s._ingested_at) AS _ingested_at,
  sort_array(filter(array(
    CASE WHEN d.versions > 1 THEN 'DIMENSION_AMBIGUITY' END,
    CASE WHEN s.Id IS NULL THEN 'INVALID_KEY' END,
    CASE WHEN s._rescued_data IS NOT NULL THEN 'RESCUED_PAYLOAD' END), x -> x IS NOT NULL)) AS reason_codes
FROM signed_revenue_centers s JOIN decisions_revenue_centers d ON s.Id <=> d.Id
WHERE d.versions > 1 OR s.Id IS NULL OR s._rescued_data IS NOT NULL
GROUP BY ALL;

