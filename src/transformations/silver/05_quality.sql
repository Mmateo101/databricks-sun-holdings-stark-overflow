-- Typed Silver contract (silver-payload-v1); deploy this checked-in SQL directly.
SET spark.sql.session.timeZone = UTC;
SET spark.sql.ansi.enabled = true;

CREATE OR REFRESH MATERIALIZED VIEW silver_quality_issues
AS SELECT 'INVALID_KEY' AS issue_code, t.location_id, t.check_id, t.business_date, t.payload_hash,
  'silver_checks' AS dataset_name, to_json(named_struct('location_id',t.location_id,'check_id',t.check_id,'business_date',t.business_date,'item_sequence',CAST(NULL AS BIGINT),'ordinal',CAST(NULL AS INT)),map('ignoreNullFields','false')) AS occurrence_key,
  '' AS reference_role, CAST(NULL AS BIGINT) AS reference_id,
  CAST(CAST(NULL AS STRING) AS STRING) AS observed_value, CAST(CAST(NULL AS STRING) AS STRING) AS expected_value,
  'silver-payload-v1' AS payload_hash_version, t.lineage.file AS _source_file,
  t._source_dt, t.lineage.ingested AS _ingested_at
FROM check_quality_versions t WHERE invalid_key=1
UNION ALL
SELECT 'RESCUED_PAYLOAD' AS issue_code, t.location_id, t.check_id, t.business_date, t.payload_hash,
  'silver_checks' AS dataset_name, to_json(named_struct('location_id',t.location_id,'check_id',t.check_id,'business_date',t.business_date,'item_sequence',CAST(NULL AS BIGINT),'ordinal',CAST(NULL AS INT)),map('ignoreNullFields','false')) AS occurrence_key,
  '' AS reference_role, CAST(NULL AS BIGINT) AS reference_id,
  CAST(CAST(NULL AS STRING) AS STRING) AS observed_value, CAST(CAST(NULL AS STRING) AS STRING) AS expected_value,
  'silver-payload-v1' AS payload_hash_version, t.lineage.file AS _source_file,
  t._source_dt, t.lineage.ingested AS _ingested_at
FROM check_quality_versions t WHERE rescued=1
UNION ALL
SELECT 'AMBIGUOUS_SEQUENCE' AS issue_code, t.location_id, t.check_id, t.business_date, t.payload_hash,
  'silver_checks' AS dataset_name, to_json(named_struct('location_id',t.location_id,'check_id',t.check_id,'business_date',t.business_date,'item_sequence',CAST(NULL AS BIGINT),'ordinal',CAST(NULL AS INT)),map('ignoreNullFields','false')) AS occurrence_key,
  '' AS reference_role, CAST(NULL AS BIGINT) AS reference_id,
  CAST(CAST(NULL AS STRING) AS STRING) AS observed_value, CAST(CAST(NULL AS STRING) AS STRING) AS expected_value,
  'silver-payload-v1' AS payload_hash_version, t.lineage.file AS _source_file,
  t._source_dt, t.lineage.ingested AS _ingested_at
FROM check_quality_versions t WHERE ambiguous_sequence=1
UNION ALL
SELECT 'CONFLICT' AS issue_code, t.location_id, t.check_id, t.business_date, t.payload_hash,
  'silver_checks' AS dataset_name, to_json(named_struct('location_id',t.location_id,'check_id',t.check_id,'business_date',t.business_date,'item_sequence',CAST(NULL AS BIGINT),'ordinal',CAST(NULL AS INT)),map('ignoreNullFields','false')) AS occurrence_key,
  '' AS reference_role, CAST(NULL AS BIGINT) AS reference_id,
  CAST(CAST(NULL AS STRING) AS STRING) AS observed_value, CAST(CAST(NULL AS STRING) AS STRING) AS expected_value,
  'silver-payload-v1' AS payload_hash_version, t.lineage.file AS _source_file,
  t._source_dt, t.lineage.ingested AS _ingested_at
FROM check_quality_versions t WHERE versions>1
UNION ALL
SELECT 'REPLAY' AS issue_code, t.location_id, t.check_id, t.business_date, t.payload_hash,
  'silver_checks' AS dataset_name, to_json(named_struct('location_id',t.location_id,'check_id',t.check_id,'business_date',t.business_date,'item_sequence',CAST(NULL AS BIGINT),'ordinal',CAST(NULL AS INT)),map('ignoreNullFields','false')) AS occurrence_key,
  '' AS reference_role, CAST(NULL AS BIGINT) AS reference_id,
  CAST(CAST(NULL AS STRING) AS STRING) AS observed_value, CAST(CAST(NULL AS STRING) AS STRING) AS expected_value,
  'silver-payload-v1' AS payload_hash_version, t.lineage.file AS _source_file,
  t._source_dt, t.lineage.ingested AS _ingested_at
FROM check_quality_versions t WHERE exact_occurrences>1
UNION ALL
SELECT 'INVALID_SOURCE_DATE' AS issue_code, t.location_id, t.check_id, t.business_date, t.payload_hash,
  'silver_checks' AS dataset_name, to_json(named_struct('location_id',t.location_id,'check_id',t.check_id,'business_date',t.business_date,'item_sequence',CAST(NULL AS BIGINT),'ordinal',CAST(NULL AS INT)),map('ignoreNullFields','false')) AS occurrence_key,
  'source_date' AS reference_role, CAST(NULL AS BIGINT) AS reference_id,
  CAST(t._source_dt AS STRING) AS observed_value, CAST('YYYY-MM-DD' AS STRING) AS expected_value,
  'silver-payload-v1' AS payload_hash_version, t.lineage.file AS _source_file,
  t._source_dt, t.lineage.ingested AS _ingested_at
FROM check_quality_versions t WHERE try_cast(t._source_dt AS DATE) IS NULL
UNION ALL
SELECT 'INVALID_TIMESTAMP' AS issue_code, t.location_id, t.check_id, t.business_date, t.payload_hash,
  'silver_checks' AS dataset_name, to_json(named_struct('location_id',t.location_id,'check_id',t.check_id,'business_date',t.business_date,'item_sequence',CAST(NULL AS BIGINT),'ordinal',CAST(NULL AS INT)),map('ignoreNullFields','false')) AS occurrence_key,
  'open_time' AS reference_role, CAST(NULL AS BIGINT) AS reference_id,
  CAST(t.OpenTime AS STRING) AS observed_value, CAST('timestamp' AS STRING) AS expected_value,
  'silver-payload-v1' AS payload_hash_version, t.lineage.file AS _source_file,
  t._source_dt, t.lineage.ingested AS _ingested_at
FROM check_quality_versions t WHERE t.OpenTime IS NOT NULL AND try_to_timestamp(t.OpenTime) IS NULL
UNION ALL
SELECT 'INVALID_TIMESTAMP' AS issue_code, t.location_id, t.check_id, t.business_date, t.payload_hash,
  'silver_checks' AS dataset_name, to_json(named_struct('location_id',t.location_id,'check_id',t.check_id,'business_date',t.business_date,'item_sequence',CAST(NULL AS BIGINT),'ordinal',CAST(NULL AS INT)),map('ignoreNullFields','false')) AS occurrence_key,
  'close_time' AS reference_role, CAST(NULL AS BIGINT) AS reference_id,
  CAST(t.CloseTime AS STRING) AS observed_value, CAST('timestamp' AS STRING) AS expected_value,
  'silver-payload-v1' AS payload_hash_version, t.lineage.file AS _source_file,
  t._source_dt, t.lineage.ingested AS _ingested_at
FROM check_quality_versions t WHERE t.CloseTime IS NOT NULL AND try_to_timestamp(t.CloseTime) IS NULL
UNION ALL
SELECT 'UNSPECIFIED_EMPLOYEE_ROLE' AS issue_code, t.location_id, t.check_id, t.business_date, t.payload_hash,
  'silver_check_items' AS dataset_name, to_json(named_struct('location_id',t.location_id,'check_id',t.check_id,'business_date',t.business_date,'item_sequence',t.item_sequence,'ordinal',CAST(NULL AS INT)),map('ignoreNullFields','false')) AS occurrence_key,
  'employee_id' AS reference_role, t.employee_id AS reference_id,
  CAST(coalesce(CAST(t.employee_id AS STRING),'NULL') AS STRING) AS observed_value, CAST('specified employee' AS STRING) AS expected_value,
  'silver-payload-v1' AS payload_hash_version, t._source_file AS _source_file,
  t._source_dt, t._ingested_at AS _ingested_at
FROM silver_check_items t WHERE t.employee_id IS NULL OR t.employee_id=0
UNION ALL
SELECT 'UNRESOLVED_REFERENCE' AS issue_code, t.location_id, t.check_id, t.business_date, t.payload_hash,
  'silver_check_items' AS dataset_name, to_json(named_struct('location_id',t.location_id,'check_id',t.check_id,'business_date',t.business_date,'item_sequence',t.item_sequence,'ordinal',CAST(NULL AS INT)),map('ignoreNullFields','false')) AS occurrence_key,
  'employee_id' AS reference_role, t.employee_id AS reference_id,
  CAST(t.employee_id AS STRING) AS observed_value, CAST('silver_employees.employee_id' AS STRING) AS expected_value,
  'silver-payload-v1' AS payload_hash_version, t._source_file AS _source_file,
  t._source_dt, t._ingested_at AS _ingested_at
FROM silver_check_items t WHERE t.employee_id>0 AND NOT EXISTS (SELECT 1 FROM silver_employees e WHERE e.employee_id=t.employee_id)
UNION ALL
SELECT 'UNSPECIFIED_EMPLOYEE_ROLE' AS issue_code, t.location_id, t.check_id, t.business_date, t.payload_hash,
  'silver_item_discounts' AS dataset_name, to_json(named_struct('location_id',t.location_id,'check_id',t.check_id,'business_date',t.business_date,'item_sequence',t.item_sequence,'ordinal',t.discount_ordinal),map('ignoreNullFields','false')) AS occurrence_key,
  'item_employee_id' AS reference_role, t.item_employee_id AS reference_id,
  CAST(coalesce(CAST(t.item_employee_id AS STRING),'NULL') AS STRING) AS observed_value, CAST('specified employee' AS STRING) AS expected_value,
  'silver-payload-v1' AS payload_hash_version, t._source_file AS _source_file,
  t._source_dt, t._ingested_at AS _ingested_at
FROM silver_item_discounts t WHERE t.item_employee_id IS NULL OR t.item_employee_id=0
UNION ALL
SELECT 'UNRESOLVED_REFERENCE' AS issue_code, t.location_id, t.check_id, t.business_date, t.payload_hash,
  'silver_item_discounts' AS dataset_name, to_json(named_struct('location_id',t.location_id,'check_id',t.check_id,'business_date',t.business_date,'item_sequence',t.item_sequence,'ordinal',t.discount_ordinal),map('ignoreNullFields','false')) AS occurrence_key,
  'item_employee_id' AS reference_role, t.item_employee_id AS reference_id,
  CAST(t.item_employee_id AS STRING) AS observed_value, CAST('silver_employees.employee_id' AS STRING) AS expected_value,
  'silver-payload-v1' AS payload_hash_version, t._source_file AS _source_file,
  t._source_dt, t._ingested_at AS _ingested_at
FROM silver_item_discounts t WHERE t.item_employee_id>0 AND NOT EXISTS (SELECT 1 FROM silver_employees e WHERE e.employee_id=t.item_employee_id)
UNION ALL
SELECT 'UNSPECIFIED_EMPLOYEE_ROLE' AS issue_code, t.location_id, t.check_id, t.business_date, t.payload_hash,
  'silver_item_discounts' AS dataset_name, to_json(named_struct('location_id',t.location_id,'check_id',t.check_id,'business_date',t.business_date,'item_sequence',t.item_sequence,'ordinal',t.discount_ordinal),map('ignoreNullFields','false')) AS occurrence_key,
  'discount_employee_id' AS reference_role, t.discount_employee_id AS reference_id,
  CAST(coalesce(CAST(t.discount_employee_id AS STRING),'NULL') AS STRING) AS observed_value, CAST('specified employee' AS STRING) AS expected_value,
  'silver-payload-v1' AS payload_hash_version, t._source_file AS _source_file,
  t._source_dt, t._ingested_at AS _ingested_at
FROM silver_item_discounts t WHERE t.discount_employee_id IS NULL OR t.discount_employee_id=0
UNION ALL
SELECT 'UNRESOLVED_REFERENCE' AS issue_code, t.location_id, t.check_id, t.business_date, t.payload_hash,
  'silver_item_discounts' AS dataset_name, to_json(named_struct('location_id',t.location_id,'check_id',t.check_id,'business_date',t.business_date,'item_sequence',t.item_sequence,'ordinal',t.discount_ordinal),map('ignoreNullFields','false')) AS occurrence_key,
  'discount_employee_id' AS reference_role, t.discount_employee_id AS reference_id,
  CAST(t.discount_employee_id AS STRING) AS observed_value, CAST('silver_employees.employee_id' AS STRING) AS expected_value,
  'silver-payload-v1' AS payload_hash_version, t._source_file AS _source_file,
  t._source_dt, t._ingested_at AS _ingested_at
FROM silver_item_discounts t WHERE t.discount_employee_id>0 AND NOT EXISTS (SELECT 1 FROM silver_employees e WHERE e.employee_id=t.discount_employee_id)
UNION ALL
SELECT 'UNSPECIFIED_EMPLOYEE_ROLE' AS issue_code, t.location_id, t.check_id, t.business_date, t.payload_hash,
  'silver_item_discounts' AS dataset_name, to_json(named_struct('location_id',t.location_id,'check_id',t.check_id,'business_date',t.business_date,'item_sequence',t.item_sequence,'ordinal',t.discount_ordinal),map('ignoreNullFields','false')) AS occurrence_key,
  'manager_id' AS reference_role, t.manager_id AS reference_id,
  CAST(coalesce(CAST(t.manager_id AS STRING),'NULL') AS STRING) AS observed_value, CAST('specified employee' AS STRING) AS expected_value,
  'silver-payload-v1' AS payload_hash_version, t._source_file AS _source_file,
  t._source_dt, t._ingested_at AS _ingested_at
FROM silver_item_discounts t WHERE t.manager_id IS NULL OR t.manager_id=0
UNION ALL
SELECT 'UNRESOLVED_REFERENCE' AS issue_code, t.location_id, t.check_id, t.business_date, t.payload_hash,
  'silver_item_discounts' AS dataset_name, to_json(named_struct('location_id',t.location_id,'check_id',t.check_id,'business_date',t.business_date,'item_sequence',t.item_sequence,'ordinal',t.discount_ordinal),map('ignoreNullFields','false')) AS occurrence_key,
  'manager_id' AS reference_role, t.manager_id AS reference_id,
  CAST(t.manager_id AS STRING) AS observed_value, CAST('silver_employees.employee_id' AS STRING) AS expected_value,
  'silver-payload-v1' AS payload_hash_version, t._source_file AS _source_file,
  t._source_dt, t._ingested_at AS _ingested_at
FROM silver_item_discounts t WHERE t.manager_id>0 AND NOT EXISTS (SELECT 1 FROM silver_employees e WHERE e.employee_id=t.manager_id)
UNION ALL
SELECT 'UNSPECIFIED_EMPLOYEE_ROLE' AS issue_code, t.location_id, t.check_id, t.business_date, t.payload_hash,
  'silver_check_discounts' AS dataset_name, to_json(named_struct('location_id',t.location_id,'check_id',t.check_id,'business_date',t.business_date,'item_sequence',CAST(NULL AS BIGINT),'ordinal',t.discount_ordinal),map('ignoreNullFields','false')) AS occurrence_key,
  'discount_employee_id' AS reference_role, t.discount_employee_id AS reference_id,
  CAST(coalesce(CAST(t.discount_employee_id AS STRING),'NULL') AS STRING) AS observed_value, CAST('specified employee' AS STRING) AS expected_value,
  'silver-payload-v1' AS payload_hash_version, t._source_file AS _source_file,
  t._source_dt, t._ingested_at AS _ingested_at
FROM silver_check_discounts t WHERE t.discount_employee_id IS NULL OR t.discount_employee_id=0
UNION ALL
SELECT 'UNRESOLVED_REFERENCE' AS issue_code, t.location_id, t.check_id, t.business_date, t.payload_hash,
  'silver_check_discounts' AS dataset_name, to_json(named_struct('location_id',t.location_id,'check_id',t.check_id,'business_date',t.business_date,'item_sequence',CAST(NULL AS BIGINT),'ordinal',t.discount_ordinal),map('ignoreNullFields','false')) AS occurrence_key,
  'discount_employee_id' AS reference_role, t.discount_employee_id AS reference_id,
  CAST(t.discount_employee_id AS STRING) AS observed_value, CAST('silver_employees.employee_id' AS STRING) AS expected_value,
  'silver-payload-v1' AS payload_hash_version, t._source_file AS _source_file,
  t._source_dt, t._ingested_at AS _ingested_at
FROM silver_check_discounts t WHERE t.discount_employee_id>0 AND NOT EXISTS (SELECT 1 FROM silver_employees e WHERE e.employee_id=t.discount_employee_id)
UNION ALL
SELECT 'UNSPECIFIED_EMPLOYEE_ROLE' AS issue_code, t.location_id, t.check_id, t.business_date, t.payload_hash,
  'silver_check_discounts' AS dataset_name, to_json(named_struct('location_id',t.location_id,'check_id',t.check_id,'business_date',t.business_date,'item_sequence',CAST(NULL AS BIGINT),'ordinal',t.discount_ordinal),map('ignoreNullFields','false')) AS occurrence_key,
  'manager_id' AS reference_role, t.manager_id AS reference_id,
  CAST(coalesce(CAST(t.manager_id AS STRING),'NULL') AS STRING) AS observed_value, CAST('specified employee' AS STRING) AS expected_value,
  'silver-payload-v1' AS payload_hash_version, t._source_file AS _source_file,
  t._source_dt, t._ingested_at AS _ingested_at
FROM silver_check_discounts t WHERE t.manager_id IS NULL OR t.manager_id=0
UNION ALL
SELECT 'UNRESOLVED_REFERENCE' AS issue_code, t.location_id, t.check_id, t.business_date, t.payload_hash,
  'silver_check_discounts' AS dataset_name, to_json(named_struct('location_id',t.location_id,'check_id',t.check_id,'business_date',t.business_date,'item_sequence',CAST(NULL AS BIGINT),'ordinal',t.discount_ordinal),map('ignoreNullFields','false')) AS occurrence_key,
  'manager_id' AS reference_role, t.manager_id AS reference_id,
  CAST(t.manager_id AS STRING) AS observed_value, CAST('silver_employees.employee_id' AS STRING) AS expected_value,
  'silver-payload-v1' AS payload_hash_version, t._source_file AS _source_file,
  t._source_dt, t._ingested_at AS _ingested_at
FROM silver_check_discounts t WHERE t.manager_id>0 AND NOT EXISTS (SELECT 1 FROM silver_employees e WHERE e.employee_id=t.manager_id)
UNION ALL
SELECT 'UNSPECIFIED_EMPLOYEE_ROLE' AS issue_code, t.location_id, t.check_id, t.business_date, t.payload_hash,
  'silver_payments' AS dataset_name, to_json(named_struct('location_id',t.location_id,'check_id',t.check_id,'business_date',t.business_date,'item_sequence',CAST(NULL AS BIGINT),'ordinal',t.payment_ordinal),map('ignoreNullFields','false')) AS occurrence_key,
  'employee_id' AS reference_role, t.employee_id AS reference_id,
  CAST(coalesce(CAST(t.employee_id AS STRING),'NULL') AS STRING) AS observed_value, CAST('specified employee' AS STRING) AS expected_value,
  'silver-payload-v1' AS payload_hash_version, t._source_file AS _source_file,
  t._source_dt, t._ingested_at AS _ingested_at
FROM silver_payments t WHERE t.employee_id IS NULL OR t.employee_id=0
UNION ALL
SELECT 'UNRESOLVED_REFERENCE' AS issue_code, t.location_id, t.check_id, t.business_date, t.payload_hash,
  'silver_payments' AS dataset_name, to_json(named_struct('location_id',t.location_id,'check_id',t.check_id,'business_date',t.business_date,'item_sequence',CAST(NULL AS BIGINT),'ordinal',t.payment_ordinal),map('ignoreNullFields','false')) AS occurrence_key,
  'employee_id' AS reference_role, t.employee_id AS reference_id,
  CAST(t.employee_id AS STRING) AS observed_value, CAST('silver_employees.employee_id' AS STRING) AS expected_value,
  'silver-payload-v1' AS payload_hash_version, t._source_file AS _source_file,
  t._source_dt, t._ingested_at AS _ingested_at
FROM silver_payments t WHERE t.employee_id>0 AND NOT EXISTS (SELECT 1 FROM silver_employees e WHERE e.employee_id=t.employee_id)
UNION ALL
SELECT 'UNSPECIFIED_EMPLOYEE_ROLE' AS issue_code, t.location_id, t.check_id, t.business_date, t.payload_hash,
  'silver_voids' AS dataset_name, to_json(named_struct('location_id',t.location_id,'check_id',t.check_id,'business_date',t.business_date,'item_sequence',CAST(NULL AS BIGINT),'ordinal',t.void_ordinal),map('ignoreNullFields','false')) AS occurrence_key,
  'employee_id' AS reference_role, t.employee_id AS reference_id,
  CAST(coalesce(CAST(t.employee_id AS STRING),'NULL') AS STRING) AS observed_value, CAST('specified employee' AS STRING) AS expected_value,
  'silver-payload-v1' AS payload_hash_version, t._source_file AS _source_file,
  t._source_dt, t._ingested_at AS _ingested_at
FROM silver_voids t WHERE t.employee_id IS NULL OR t.employee_id=0
UNION ALL
SELECT 'UNRESOLVED_REFERENCE' AS issue_code, t.location_id, t.check_id, t.business_date, t.payload_hash,
  'silver_voids' AS dataset_name, to_json(named_struct('location_id',t.location_id,'check_id',t.check_id,'business_date',t.business_date,'item_sequence',CAST(NULL AS BIGINT),'ordinal',t.void_ordinal),map('ignoreNullFields','false')) AS occurrence_key,
  'employee_id' AS reference_role, t.employee_id AS reference_id,
  CAST(t.employee_id AS STRING) AS observed_value, CAST('silver_employees.employee_id' AS STRING) AS expected_value,
  'silver-payload-v1' AS payload_hash_version, t._source_file AS _source_file,
  t._source_dt, t._ingested_at AS _ingested_at
FROM silver_voids t WHERE t.employee_id>0 AND NOT EXISTS (SELECT 1 FROM silver_employees e WHERE e.employee_id=t.employee_id)
UNION ALL
SELECT 'UNSPECIFIED_EMPLOYEE_ROLE' AS issue_code, t.location_id, t.check_id, t.business_date, t.payload_hash,
  'silver_voids' AS dataset_name, to_json(named_struct('location_id',t.location_id,'check_id',t.check_id,'business_date',t.business_date,'item_sequence',CAST(NULL AS BIGINT),'ordinal',t.void_ordinal),map('ignoreNullFields','false')) AS occurrence_key,
  'manager_id' AS reference_role, t.manager_id AS reference_id,
  CAST(coalesce(CAST(t.manager_id AS STRING),'NULL') AS STRING) AS observed_value, CAST('specified employee' AS STRING) AS expected_value,
  'silver-payload-v1' AS payload_hash_version, t._source_file AS _source_file,
  t._source_dt, t._ingested_at AS _ingested_at
FROM silver_voids t WHERE t.manager_id IS NULL OR t.manager_id=0
UNION ALL
SELECT 'UNRESOLVED_REFERENCE' AS issue_code, t.location_id, t.check_id, t.business_date, t.payload_hash,
  'silver_voids' AS dataset_name, to_json(named_struct('location_id',t.location_id,'check_id',t.check_id,'business_date',t.business_date,'item_sequence',CAST(NULL AS BIGINT),'ordinal',t.void_ordinal),map('ignoreNullFields','false')) AS occurrence_key,
  'manager_id' AS reference_role, t.manager_id AS reference_id,
  CAST(t.manager_id AS STRING) AS observed_value, CAST('silver_employees.employee_id' AS STRING) AS expected_value,
  'silver-payload-v1' AS payload_hash_version, t._source_file AS _source_file,
  t._source_dt, t._ingested_at AS _ingested_at
FROM silver_voids t WHERE t.manager_id>0 AND NOT EXISTS (SELECT 1 FROM silver_employees e WHERE e.employee_id=t.manager_id)
UNION ALL
SELECT 'UNRESOLVED_REFERENCE' AS issue_code, t.location_id, t.check_id, t.business_date, t.payload_hash,
  'silver_checks' AS dataset_name, to_json(named_struct('location_id',t.location_id,'check_id',t.check_id,'business_date',t.business_date,'item_sequence',CAST(NULL AS BIGINT),'ordinal',CAST(NULL AS INT)),map('ignoreNullFields','false')) AS occurrence_key,
  'location_id' AS reference_role, t.location_id AS reference_id,
  CAST(t.location_id AS STRING) AS observed_value, CAST('silver_locations.location_id' AS STRING) AS expected_value,
  'silver-payload-v1' AS payload_hash_version, t._source_file AS _source_file,
  t._source_dt, t._ingested_at AS _ingested_at
FROM silver_checks t WHERE t.location_id>0 AND NOT EXISTS (SELECT 1 FROM silver_locations d WHERE d.location_id=t.location_id)
UNION ALL
SELECT 'UNRESOLVED_REFERENCE' AS issue_code, t.location_id, t.check_id, t.business_date, t.payload_hash,
  'silver_checks' AS dataset_name, to_json(named_struct('location_id',t.location_id,'check_id',t.check_id,'business_date',t.business_date,'item_sequence',CAST(NULL AS BIGINT),'ordinal',CAST(NULL AS INT)),map('ignoreNullFields','false')) AS occurrence_key,
  'revenue_center_id' AS reference_role, t.revenue_center_id AS reference_id,
  CAST(t.revenue_center_id AS STRING) AS observed_value, CAST('silver_revenue_centers.revenue_center_id' AS STRING) AS expected_value,
  'silver-payload-v1' AS payload_hash_version, t._source_file AS _source_file,
  t._source_dt, t._ingested_at AS _ingested_at
FROM silver_checks t WHERE t.revenue_center_id>0 AND NOT EXISTS (SELECT 1 FROM silver_revenue_centers d WHERE d.revenue_center_id=t.revenue_center_id)
UNION ALL
SELECT 'UNRESOLVED_REFERENCE' AS issue_code, t.location_id, t.check_id, t.business_date, t.payload_hash,
  'silver_check_items' AS dataset_name, to_json(named_struct('location_id',t.location_id,'check_id',t.check_id,'business_date',t.business_date,'item_sequence',t.item_sequence,'ordinal',CAST(NULL AS INT)),map('ignoreNullFields','false')) AS occurrence_key,
  'item_id' AS reference_role, t.item_id AS reference_id,
  CAST(t.item_id AS STRING) AS observed_value, CAST('silver_items.item_id' AS STRING) AS expected_value,
  'silver-payload-v1' AS payload_hash_version, t._source_file AS _source_file,
  t._source_dt, t._ingested_at AS _ingested_at
FROM silver_check_items t WHERE t.item_id>0 AND NOT EXISTS (SELECT 1 FROM silver_items d WHERE d.item_id=t.item_id)
UNION ALL
SELECT 'UNRESOLVED_REFERENCE' AS issue_code, t.location_id, t.check_id, t.business_date, t.payload_hash,
  'silver_voids' AS dataset_name, to_json(named_struct('location_id',t.location_id,'check_id',t.check_id,'business_date',t.business_date,'item_sequence',CAST(NULL AS BIGINT),'ordinal',t.void_ordinal),map('ignoreNullFields','false')) AS occurrence_key,
  'item_id' AS reference_role, t.item_id AS reference_id,
  CAST(t.item_id AS STRING) AS observed_value, CAST('silver_items.item_id' AS STRING) AS expected_value,
  'silver-payload-v1' AS payload_hash_version, t._source_file AS _source_file,
  t._source_dt, t._ingested_at AS _ingested_at
FROM silver_voids t WHERE t.item_id>0 AND NOT EXISTS (SELECT 1 FROM silver_items d WHERE d.item_id=t.item_id)
UNION ALL
SELECT 'UNRESOLVED_REFERENCE' AS issue_code, t.location_id, t.check_id, t.business_date, t.payload_hash,
  'silver_check_items' AS dataset_name, to_json(named_struct('location_id',t.location_id,'check_id',t.check_id,'business_date',t.business_date,'item_sequence',t.item_sequence,'ordinal',CAST(NULL AS INT)),map('ignoreNullFields','false')) AS occurrence_key,
  'revenue_center_id' AS reference_role, t.revenue_center_id AS reference_id,
  CAST(t.revenue_center_id AS STRING) AS observed_value, CAST('silver_revenue_centers.revenue_center_id' AS STRING) AS expected_value,
  'silver-payload-v1' AS payload_hash_version, t._source_file AS _source_file,
  t._source_dt, t._ingested_at AS _ingested_at
FROM silver_check_items t WHERE t.revenue_center_id>0 AND NOT EXISTS (SELECT 1 FROM silver_revenue_centers d WHERE d.revenue_center_id=t.revenue_center_id)
UNION ALL
SELECT 'UNRESOLVED_REFERENCE' AS issue_code, t.location_id, t.check_id, t.business_date, t.payload_hash,
  'silver_check_items' AS dataset_name, to_json(named_struct('location_id',t.location_id,'check_id',t.check_id,'business_date',t.business_date,'item_sequence',t.item_sequence,'ordinal',CAST(NULL AS INT)),map('ignoreNullFields','false')) AS occurrence_key,
  'parent_sequence' AS reference_role, t.parent_sequence AS reference_id,
  CAST(t.parent_sequence AS STRING) AS observed_value, CAST('same K item_sequence' AS STRING) AS expected_value,
  'silver-payload-v1' AS payload_hash_version, t._source_file AS _source_file,
  t._source_dt, t._ingested_at AS _ingested_at
FROM silver_check_items t WHERE t.parent_sequence>0 AND NOT EXISTS (SELECT 1 FROM silver_check_items p WHERE p.location_id=t.location_id AND p.check_id=t.check_id AND p.business_date=t.business_date AND p.item_sequence=t.parent_sequence)
UNION ALL
SELECT 'NEGATIVE_PRICE' AS issue_code, t.location_id, t.check_id, t.business_date, t.payload_hash,
  'silver_check_items' AS dataset_name, to_json(named_struct('location_id',t.location_id,'check_id',t.check_id,'business_date',t.business_date,'item_sequence',t.item_sequence,'ordinal',CAST(NULL AS INT)),map('ignoreNullFields','false')) AS occurrence_key,
  'gross_price' AS reference_role, CAST(NULL AS BIGINT) AS reference_id,
  CAST(t.gross_price AS STRING) AS observed_value, CAST('nonnegative' AS STRING) AS expected_value,
  'silver-payload-v1' AS payload_hash_version, t._source_file AS _source_file,
  t._source_dt, t._ingested_at AS _ingested_at
FROM silver_check_items t WHERE t.gross_price<0
UNION ALL
SELECT 'NEGATIVE_PRICE' AS issue_code, t.location_id, t.check_id, t.business_date, t.payload_hash,
  'silver_check_items' AS dataset_name, to_json(named_struct('location_id',t.location_id,'check_id',t.check_id,'business_date',t.business_date,'item_sequence',t.item_sequence,'ordinal',CAST(NULL AS INT)),map('ignoreNullFields','false')) AS occurrence_key,
  'sold_price' AS reference_role, CAST(NULL AS BIGINT) AS reference_id,
  CAST(t.sold_price AS STRING) AS observed_value, CAST('nonnegative' AS STRING) AS expected_value,
  'silver-payload-v1' AS payload_hash_version, t._source_file AS _source_file,
  t._source_dt, t._ingested_at AS _ingested_at
FROM silver_check_items t WHERE t.sold_price<0
UNION ALL
SELECT 'INVALID_TIMESTAMP' AS issue_code, t.location_id, t.check_id, t.business_date, t.payload_hash,
  'silver_check_items' AS dataset_name, to_json(named_struct('location_id',t.location_id,'check_id',t.check_id,'business_date',t.business_date,'item_sequence',t.item_sequence,'ordinal',CAST(NULL AS INT)),map('ignoreNullFields','false')) AS occurrence_key,
  'order_time' AS reference_role, CAST(NULL AS BIGINT) AS reference_id,
  CAST(t.OrderTime AS STRING) AS observed_value, CAST('timestamp' AS STRING) AS expected_value,
  'silver-payload-v1' AS payload_hash_version, t._source_file AS _source_file,
  t._source_dt, t._ingested_at AS _ingested_at
FROM (SELECT c.Id AS check_id, c.LocationId AS location_id, c.business_date, c.payload_hash, c.payload_hash_version, c._source_file, c._source_dt, c._ingested_at, c.source_files, c.replay_count, i.Sequence AS item_sequence, i.OrderTime
FROM accepted_checks c LATERAL VIEW explode(c.ItemsSold) a AS i) t WHERE t.OrderTime IS NOT NULL AND try_to_timestamp(t.OrderTime) IS NULL
UNION ALL
SELECT 'ACCOUNTING_DISCREPANCY' AS issue_code, t.location_id, t.check_id, t.business_date, t.payload_hash,
  'silver_check_items' AS dataset_name, to_json(named_struct('location_id',t.location_id,'check_id',t.check_id,'business_date',t.business_date,'item_sequence',t.item_sequence,'ordinal',CAST(NULL AS INT)),map('ignoreNullFields','false')) AS occurrence_key,
  'item_gross_less_discount' AS reference_role, CAST(NULL AS BIGINT) AS reference_id,
  CAST(t.sold_price AS STRING) AS observed_value, CAST(t.gross_price-t.item_discount_amount AS STRING) AS expected_value,
  'silver-payload-v1' AS payload_hash_version, t._source_file AS _source_file,
  t._source_dt, t._ingested_at AS _ingested_at
FROM silver_check_items t WHERE abs(t.gross_price-t.item_discount_amount-t.sold_price)>0.01
UNION ALL
SELECT 'ACCOUNTING_DISCREPANCY' AS issue_code, t.location_id, t.check_id, t.business_date, t.payload_hash,
  'silver_checks' AS dataset_name, to_json(named_struct('location_id',t.location_id,'check_id',t.check_id,'business_date',t.business_date,'item_sequence',CAST(NULL AS BIGINT),'ordinal',CAST(NULL AS INT)),map('ignoreNullFields','false')) AS occurrence_key,
  'check_net' AS reference_role, CAST(NULL AS BIGINT) AS reference_id,
  CAST(coalesce(t.payment_net,0) AS STRING) AS observed_value, CAST(coalesce(t.sold_net,0)-coalesce(t.discount_total,0)+coalesce(t.tax_total,0)+coalesce(t.service_charge,0) AS STRING) AS expected_value,
  'silver-payload-v1' AS payload_hash_version, t._source_file AS _source_file,
  t._source_dt, t._ingested_at AS _ingested_at
FROM (SELECT c.*, p.payment_net, i.sold_net, d.discount_total, x.tax_total
FROM silver_checks c
LEFT JOIN (SELECT location_id,check_id,business_date,sum(amount+gratuity_raw) AS payment_net FROM silver_payments GROUP BY ALL) p USING(location_id,check_id,business_date)
LEFT JOIN (SELECT location_id,check_id,business_date,sum(sold_price) AS sold_net FROM silver_check_items GROUP BY ALL) i USING(location_id,check_id,business_date)
LEFT JOIN (SELECT location_id,check_id,business_date,sum(amount) AS discount_total FROM silver_check_discounts GROUP BY ALL) d USING(location_id,check_id,business_date)
LEFT JOIN (SELECT location_id,check_id,business_date,sum(amount) AS tax_total FROM silver_taxes GROUP BY ALL) x USING(location_id,check_id,business_date)) t WHERE abs(coalesce(t.payment_net,0)-(coalesce(t.sold_net,0)-coalesce(t.discount_total,0)+coalesce(t.tax_total,0)+coalesce(t.service_charge,0)))>0.01
UNION ALL
SELECT 'NULL_NUMERIC_VALUE' AS issue_code, t.location_id, t.check_id, t.business_date, t.payload_hash,
  'silver_checks' AS dataset_name, to_json(named_struct('location_id',t.location_id,'check_id',t.check_id,'business_date',t.business_date,'item_sequence',CAST(NULL AS BIGINT),'ordinal',CAST(NULL AS INT)),map('ignoreNullFields','false')) AS occurrence_key,
  'traffic_count' AS reference_role, CAST(NULL AS BIGINT) AS reference_id,
  CAST('NULL' AS STRING) AS observed_value, CAST('non-null numeric' AS STRING) AS expected_value,
  'silver-payload-v1' AS payload_hash_version, t._source_file AS _source_file,
  t._source_dt, t._ingested_at AS _ingested_at
FROM silver_checks t WHERE t.traffic_count IS NULL
UNION ALL
SELECT 'NULL_NUMERIC_VALUE' AS issue_code, t.location_id, t.check_id, t.business_date, t.payload_hash,
  'silver_checks' AS dataset_name, to_json(named_struct('location_id',t.location_id,'check_id',t.check_id,'business_date',t.business_date,'item_sequence',CAST(NULL AS BIGINT),'ordinal',CAST(NULL AS INT)),map('ignoreNullFields','false')) AS occurrence_key,
  'service_charge' AS reference_role, CAST(NULL AS BIGINT) AS reference_id,
  CAST('NULL' AS STRING) AS observed_value, CAST('non-null numeric' AS STRING) AS expected_value,
  'silver-payload-v1' AS payload_hash_version, t._source_file AS _source_file,
  t._source_dt, t._ingested_at AS _ingested_at
FROM silver_checks t WHERE t.service_charge IS NULL
UNION ALL
SELECT 'NULL_NUMERIC_VALUE' AS issue_code, t.location_id, t.check_id, t.business_date, t.payload_hash,
  'silver_check_items' AS dataset_name, to_json(named_struct('location_id',t.location_id,'check_id',t.check_id,'business_date',t.business_date,'item_sequence',t.item_sequence,'ordinal',CAST(NULL AS INT)),map('ignoreNullFields','false')) AS occurrence_key,
  'quantity' AS reference_role, CAST(NULL AS BIGINT) AS reference_id,
  CAST('NULL' AS STRING) AS observed_value, CAST('non-null numeric' AS STRING) AS expected_value,
  'silver-payload-v1' AS payload_hash_version, t._source_file AS _source_file,
  t._source_dt, t._ingested_at AS _ingested_at
FROM silver_check_items t WHERE t.quantity IS NULL
UNION ALL
SELECT 'NULL_NUMERIC_VALUE' AS issue_code, t.location_id, t.check_id, t.business_date, t.payload_hash,
  'silver_check_items' AS dataset_name, to_json(named_struct('location_id',t.location_id,'check_id',t.check_id,'business_date',t.business_date,'item_sequence',t.item_sequence,'ordinal',CAST(NULL AS INT)),map('ignoreNullFields','false')) AS occurrence_key,
  'gross_price' AS reference_role, CAST(NULL AS BIGINT) AS reference_id,
  CAST('NULL' AS STRING) AS observed_value, CAST('non-null numeric' AS STRING) AS expected_value,
  'silver-payload-v1' AS payload_hash_version, t._source_file AS _source_file,
  t._source_dt, t._ingested_at AS _ingested_at
FROM silver_check_items t WHERE t.gross_price IS NULL
UNION ALL
SELECT 'NULL_NUMERIC_VALUE' AS issue_code, t.location_id, t.check_id, t.business_date, t.payload_hash,
  'silver_check_items' AS dataset_name, to_json(named_struct('location_id',t.location_id,'check_id',t.check_id,'business_date',t.business_date,'item_sequence',t.item_sequence,'ordinal',CAST(NULL AS INT)),map('ignoreNullFields','false')) AS occurrence_key,
  'sold_price' AS reference_role, CAST(NULL AS BIGINT) AS reference_id,
  CAST('NULL' AS STRING) AS observed_value, CAST('non-null numeric' AS STRING) AS expected_value,
  'silver-payload-v1' AS payload_hash_version, t._source_file AS _source_file,
  t._source_dt, t._ingested_at AS _ingested_at
FROM silver_check_items t WHERE t.sold_price IS NULL
UNION ALL
SELECT 'NULL_NUMERIC_VALUE' AS issue_code, t.location_id, t.check_id, t.business_date, t.payload_hash,
  'silver_item_discounts' AS dataset_name, to_json(named_struct('location_id',t.location_id,'check_id',t.check_id,'business_date',t.business_date,'item_sequence',t.item_sequence,'ordinal',t.discount_ordinal),map('ignoreNullFields','false')) AS occurrence_key,
  'amount' AS reference_role, CAST(NULL AS BIGINT) AS reference_id,
  CAST('NULL' AS STRING) AS observed_value, CAST('non-null numeric' AS STRING) AS expected_value,
  'silver-payload-v1' AS payload_hash_version, t._source_file AS _source_file,
  t._source_dt, t._ingested_at AS _ingested_at
FROM silver_item_discounts t WHERE t.amount IS NULL
UNION ALL
SELECT 'NULL_NUMERIC_VALUE' AS issue_code, t.location_id, t.check_id, t.business_date, t.payload_hash,
  'silver_check_discounts' AS dataset_name, to_json(named_struct('location_id',t.location_id,'check_id',t.check_id,'business_date',t.business_date,'item_sequence',CAST(NULL AS BIGINT),'ordinal',t.discount_ordinal),map('ignoreNullFields','false')) AS occurrence_key,
  'amount' AS reference_role, CAST(NULL AS BIGINT) AS reference_id,
  CAST('NULL' AS STRING) AS observed_value, CAST('non-null numeric' AS STRING) AS expected_value,
  'silver-payload-v1' AS payload_hash_version, t._source_file AS _source_file,
  t._source_dt, t._ingested_at AS _ingested_at
FROM silver_check_discounts t WHERE t.amount IS NULL
UNION ALL
SELECT 'NULL_NUMERIC_VALUE' AS issue_code, t.location_id, t.check_id, t.business_date, t.payload_hash,
  'silver_payments' AS dataset_name, to_json(named_struct('location_id',t.location_id,'check_id',t.check_id,'business_date',t.business_date,'item_sequence',CAST(NULL AS BIGINT),'ordinal',t.payment_ordinal),map('ignoreNullFields','false')) AS occurrence_key,
  'amount' AS reference_role, CAST(NULL AS BIGINT) AS reference_id,
  CAST('NULL' AS STRING) AS observed_value, CAST('non-null numeric' AS STRING) AS expected_value,
  'silver-payload-v1' AS payload_hash_version, t._source_file AS _source_file,
  t._source_dt, t._ingested_at AS _ingested_at
FROM silver_payments t WHERE t.amount IS NULL
UNION ALL
SELECT 'NULL_NUMERIC_VALUE' AS issue_code, t.location_id, t.check_id, t.business_date, t.payload_hash,
  'silver_payments' AS dataset_name, to_json(named_struct('location_id',t.location_id,'check_id',t.check_id,'business_date',t.business_date,'item_sequence',CAST(NULL AS BIGINT),'ordinal',t.payment_ordinal),map('ignoreNullFields','false')) AS occurrence_key,
  'gratuity_raw' AS reference_role, CAST(NULL AS BIGINT) AS reference_id,
  CAST('NULL' AS STRING) AS observed_value, CAST('non-null numeric' AS STRING) AS expected_value,
  'silver-payload-v1' AS payload_hash_version, t._source_file AS _source_file,
  t._source_dt, t._ingested_at AS _ingested_at
FROM silver_payments t WHERE t.gratuity_raw IS NULL
UNION ALL
SELECT 'NULL_NUMERIC_VALUE' AS issue_code, t.location_id, t.check_id, t.business_date, t.payload_hash,
  'silver_taxes' AS dataset_name, to_json(named_struct('location_id',t.location_id,'check_id',t.check_id,'business_date',t.business_date,'item_sequence',CAST(NULL AS BIGINT),'ordinal',t.tax_ordinal),map('ignoreNullFields','false')) AS occurrence_key,
  'amount' AS reference_role, CAST(NULL AS BIGINT) AS reference_id,
  CAST('NULL' AS STRING) AS observed_value, CAST('non-null numeric' AS STRING) AS expected_value,
  'silver-payload-v1' AS payload_hash_version, t._source_file AS _source_file,
  t._source_dt, t._ingested_at AS _ingested_at
FROM silver_taxes t WHERE t.amount IS NULL
UNION ALL
SELECT 'NULL_NUMERIC_VALUE' AS issue_code, t.location_id, t.check_id, t.business_date, t.payload_hash,
  'silver_voids' AS dataset_name, to_json(named_struct('location_id',t.location_id,'check_id',t.check_id,'business_date',t.business_date,'item_sequence',CAST(NULL AS BIGINT),'ordinal',t.void_ordinal),map('ignoreNullFields','false')) AS occurrence_key,
  'quantity' AS reference_role, CAST(NULL AS BIGINT) AS reference_id,
  CAST('NULL' AS STRING) AS observed_value, CAST('non-null numeric' AS STRING) AS expected_value,
  'silver-payload-v1' AS payload_hash_version, t._source_file AS _source_file,
  t._source_dt, t._ingested_at AS _ingested_at
FROM silver_voids t WHERE t.quantity IS NULL
UNION ALL
SELECT 'NULL_NUMERIC_VALUE' AS issue_code, t.location_id, t.check_id, t.business_date, t.payload_hash,
  'silver_voids' AS dataset_name, to_json(named_struct('location_id',t.location_id,'check_id',t.check_id,'business_date',t.business_date,'item_sequence',CAST(NULL AS BIGINT),'ordinal',t.void_ordinal),map('ignoreNullFields','false')) AS occurrence_key,
  'amount' AS reference_role, CAST(NULL AS BIGINT) AS reference_id,
  CAST('NULL' AS STRING) AS observed_value, CAST('non-null numeric' AS STRING) AS expected_value,
  'silver-payload-v1' AS payload_hash_version, t._source_file AS _source_file,
  t._source_dt, t._ingested_at AS _ingested_at
FROM silver_voids t WHERE t.amount IS NULL
UNION ALL
SELECT 'DIMENSION_AMBIGUITY' AS issue_code, CAST(NULL AS BIGINT) AS location_id, CAST(NULL AS BIGINT) AS check_id,
  CAST(NULL AS DATE) AS business_date, t.payload_hash, 'silver_employees' AS dataset_name,
  to_json(named_struct('dimension_id',t.Id),map('ignoreNullFields','false')) AS occurrence_key,
  'dimension_id' AS reference_role, t.Id AS reference_id, t.canonical_payload AS observed_value,
  'one current payload per supplied ID' AS expected_value, CAST(NULL AS STRING) AS payload_hash_version,
  t._source_file, t._source_dt, t._ingested_at
FROM (SELECT s.* EXCEPT (_ingested_at), min(s._ingested_at) AS _ingested_at, d.versions
FROM signed_employees s JOIN decisions_employees d ON s.Id <=> d.Id GROUP BY ALL) t WHERE t.versions>1
UNION ALL
SELECT 'INVALID_KEY' AS issue_code, CAST(NULL AS BIGINT) AS location_id, CAST(NULL AS BIGINT) AS check_id,
  CAST(NULL AS DATE) AS business_date, t.payload_hash, 'silver_employees' AS dataset_name,
  to_json(named_struct('dimension_id',t.Id),map('ignoreNullFields','false')) AS occurrence_key,
  'dimension_id' AS reference_role, t.Id AS reference_id, t.canonical_payload AS observed_value,
  'one current payload per supplied ID' AS expected_value, CAST(NULL AS STRING) AS payload_hash_version,
  t._source_file, t._source_dt, t._ingested_at
FROM (SELECT s.* EXCEPT (_ingested_at), min(s._ingested_at) AS _ingested_at, d.versions
FROM signed_employees s JOIN decisions_employees d ON s.Id <=> d.Id GROUP BY ALL) t WHERE t.Id IS NULL
UNION ALL
SELECT 'RESCUED_PAYLOAD' AS issue_code, CAST(NULL AS BIGINT) AS location_id, CAST(NULL AS BIGINT) AS check_id,
  CAST(NULL AS DATE) AS business_date, t.payload_hash, 'silver_employees' AS dataset_name,
  to_json(named_struct('dimension_id',t.Id),map('ignoreNullFields','false')) AS occurrence_key,
  'dimension_id' AS reference_role, t.Id AS reference_id, t.canonical_payload AS observed_value,
  'one current payload per supplied ID' AS expected_value, CAST(NULL AS STRING) AS payload_hash_version,
  t._source_file, t._source_dt, t._ingested_at
FROM (SELECT s.* EXCEPT (_ingested_at), min(s._ingested_at) AS _ingested_at, d.versions
FROM signed_employees s JOIN decisions_employees d ON s.Id <=> d.Id GROUP BY ALL) t WHERE t._rescued_data IS NOT NULL
UNION ALL
SELECT 'DIMENSION_AMBIGUITY' AS issue_code, CAST(NULL AS BIGINT) AS location_id, CAST(NULL AS BIGINT) AS check_id,
  CAST(NULL AS DATE) AS business_date, t.payload_hash, 'silver_items' AS dataset_name,
  to_json(named_struct('dimension_id',t.Id),map('ignoreNullFields','false')) AS occurrence_key,
  'dimension_id' AS reference_role, t.Id AS reference_id, t.canonical_payload AS observed_value,
  'one current payload per supplied ID' AS expected_value, CAST(NULL AS STRING) AS payload_hash_version,
  t._source_file, t._source_dt, t._ingested_at
FROM (SELECT s.* EXCEPT (_ingested_at), min(s._ingested_at) AS _ingested_at, d.versions
FROM signed_items s JOIN decisions_items d ON s.Id <=> d.Id GROUP BY ALL) t WHERE t.versions>1
UNION ALL
SELECT 'INVALID_KEY' AS issue_code, CAST(NULL AS BIGINT) AS location_id, CAST(NULL AS BIGINT) AS check_id,
  CAST(NULL AS DATE) AS business_date, t.payload_hash, 'silver_items' AS dataset_name,
  to_json(named_struct('dimension_id',t.Id),map('ignoreNullFields','false')) AS occurrence_key,
  'dimension_id' AS reference_role, t.Id AS reference_id, t.canonical_payload AS observed_value,
  'one current payload per supplied ID' AS expected_value, CAST(NULL AS STRING) AS payload_hash_version,
  t._source_file, t._source_dt, t._ingested_at
FROM (SELECT s.* EXCEPT (_ingested_at), min(s._ingested_at) AS _ingested_at, d.versions
FROM signed_items s JOIN decisions_items d ON s.Id <=> d.Id GROUP BY ALL) t WHERE t.Id IS NULL
UNION ALL
SELECT 'RESCUED_PAYLOAD' AS issue_code, CAST(NULL AS BIGINT) AS location_id, CAST(NULL AS BIGINT) AS check_id,
  CAST(NULL AS DATE) AS business_date, t.payload_hash, 'silver_items' AS dataset_name,
  to_json(named_struct('dimension_id',t.Id),map('ignoreNullFields','false')) AS occurrence_key,
  'dimension_id' AS reference_role, t.Id AS reference_id, t.canonical_payload AS observed_value,
  'one current payload per supplied ID' AS expected_value, CAST(NULL AS STRING) AS payload_hash_version,
  t._source_file, t._source_dt, t._ingested_at
FROM (SELECT s.* EXCEPT (_ingested_at), min(s._ingested_at) AS _ingested_at, d.versions
FROM signed_items s JOIN decisions_items d ON s.Id <=> d.Id GROUP BY ALL) t WHERE t._rescued_data IS NOT NULL
UNION ALL
SELECT 'DIMENSION_AMBIGUITY' AS issue_code, CAST(NULL AS BIGINT) AS location_id, CAST(NULL AS BIGINT) AS check_id,
  CAST(NULL AS DATE) AS business_date, t.payload_hash, 'silver_locations' AS dataset_name,
  to_json(named_struct('dimension_id',t.Id),map('ignoreNullFields','false')) AS occurrence_key,
  'dimension_id' AS reference_role, t.Id AS reference_id, t.canonical_payload AS observed_value,
  'one current payload per supplied ID' AS expected_value, CAST(NULL AS STRING) AS payload_hash_version,
  t._source_file, t._source_dt, t._ingested_at
FROM (SELECT s.* EXCEPT (_ingested_at), min(s._ingested_at) AS _ingested_at, d.versions
FROM signed_locations s JOIN decisions_locations d ON s.Id <=> d.Id GROUP BY ALL) t WHERE t.versions>1
UNION ALL
SELECT 'INVALID_KEY' AS issue_code, CAST(NULL AS BIGINT) AS location_id, CAST(NULL AS BIGINT) AS check_id,
  CAST(NULL AS DATE) AS business_date, t.payload_hash, 'silver_locations' AS dataset_name,
  to_json(named_struct('dimension_id',t.Id),map('ignoreNullFields','false')) AS occurrence_key,
  'dimension_id' AS reference_role, t.Id AS reference_id, t.canonical_payload AS observed_value,
  'one current payload per supplied ID' AS expected_value, CAST(NULL AS STRING) AS payload_hash_version,
  t._source_file, t._source_dt, t._ingested_at
FROM (SELECT s.* EXCEPT (_ingested_at), min(s._ingested_at) AS _ingested_at, d.versions
FROM signed_locations s JOIN decisions_locations d ON s.Id <=> d.Id GROUP BY ALL) t WHERE t.Id IS NULL
UNION ALL
SELECT 'RESCUED_PAYLOAD' AS issue_code, CAST(NULL AS BIGINT) AS location_id, CAST(NULL AS BIGINT) AS check_id,
  CAST(NULL AS DATE) AS business_date, t.payload_hash, 'silver_locations' AS dataset_name,
  to_json(named_struct('dimension_id',t.Id),map('ignoreNullFields','false')) AS occurrence_key,
  'dimension_id' AS reference_role, t.Id AS reference_id, t.canonical_payload AS observed_value,
  'one current payload per supplied ID' AS expected_value, CAST(NULL AS STRING) AS payload_hash_version,
  t._source_file, t._source_dt, t._ingested_at
FROM (SELECT s.* EXCEPT (_ingested_at), min(s._ingested_at) AS _ingested_at, d.versions
FROM signed_locations s JOIN decisions_locations d ON s.Id <=> d.Id GROUP BY ALL) t WHERE t._rescued_data IS NOT NULL
UNION ALL
SELECT 'DIMENSION_AMBIGUITY' AS issue_code, CAST(NULL AS BIGINT) AS location_id, CAST(NULL AS BIGINT) AS check_id,
  CAST(NULL AS DATE) AS business_date, t.payload_hash, 'silver_revenue_centers' AS dataset_name,
  to_json(named_struct('dimension_id',t.Id),map('ignoreNullFields','false')) AS occurrence_key,
  'dimension_id' AS reference_role, t.Id AS reference_id, t.canonical_payload AS observed_value,
  'one current payload per supplied ID' AS expected_value, CAST(NULL AS STRING) AS payload_hash_version,
  t._source_file, t._source_dt, t._ingested_at
FROM (SELECT s.* EXCEPT (_ingested_at), min(s._ingested_at) AS _ingested_at, d.versions
FROM signed_revenue_centers s JOIN decisions_revenue_centers d ON s.Id <=> d.Id GROUP BY ALL) t WHERE t.versions>1
UNION ALL
SELECT 'INVALID_KEY' AS issue_code, CAST(NULL AS BIGINT) AS location_id, CAST(NULL AS BIGINT) AS check_id,
  CAST(NULL AS DATE) AS business_date, t.payload_hash, 'silver_revenue_centers' AS dataset_name,
  to_json(named_struct('dimension_id',t.Id),map('ignoreNullFields','false')) AS occurrence_key,
  'dimension_id' AS reference_role, t.Id AS reference_id, t.canonical_payload AS observed_value,
  'one current payload per supplied ID' AS expected_value, CAST(NULL AS STRING) AS payload_hash_version,
  t._source_file, t._source_dt, t._ingested_at
FROM (SELECT s.* EXCEPT (_ingested_at), min(s._ingested_at) AS _ingested_at, d.versions
FROM signed_revenue_centers s JOIN decisions_revenue_centers d ON s.Id <=> d.Id GROUP BY ALL) t WHERE t.Id IS NULL
UNION ALL
SELECT 'RESCUED_PAYLOAD' AS issue_code, CAST(NULL AS BIGINT) AS location_id, CAST(NULL AS BIGINT) AS check_id,
  CAST(NULL AS DATE) AS business_date, t.payload_hash, 'silver_revenue_centers' AS dataset_name,
  to_json(named_struct('dimension_id',t.Id),map('ignoreNullFields','false')) AS occurrence_key,
  'dimension_id' AS reference_role, t.Id AS reference_id, t.canonical_payload AS observed_value,
  'one current payload per supplied ID' AS expected_value, CAST(NULL AS STRING) AS payload_hash_version,
  t._source_file, t._source_dt, t._ingested_at
FROM (SELECT s.* EXCEPT (_ingested_at), min(s._ingested_at) AS _ingested_at, d.versions
FROM signed_revenue_centers s JOIN decisions_revenue_centers d ON s.Id <=> d.Id GROUP BY ALL) t WHERE t._rescued_data IS NOT NULL;

