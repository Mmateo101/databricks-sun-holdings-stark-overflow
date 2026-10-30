-- Typed Silver contract (silver-payload-v1); deploy this checked-in SQL directly.
SET spark.sql.session.timeZone = UTC;
SET spark.sql.ansi.enabled = true;

-- Fixed schemas are the silver-payload-v1 typed business contract.
CREATE OR REFRESH PRIVATE STREAMING TABLE raw_checks
AS SELECT *, _metadata.file_path AS _source_file,
  regexp_extract(_metadata.file_path, 'dt=([0-9-]+)', 1) AS _source_dt,
  current_timestamp() AS _ingested_at
FROM STREAM read_files(
  '${source_root}/checks/',
  format => 'json', multiLine => false, partitionColumns => '',
  schema => 'BusinessDate string, CloseTime string, Discounts array<struct<Amount:double,DiscountId:bigint,DiscountName:string,EmployeeId:bigint,ManagerId:bigint>>, Id bigint, ItemsSold array<struct<Discounts:array<struct<Amount:double,DiscountId:bigint,DiscountName:string,EmployeeId:bigint,ManagerId:bigint>>,EmployeeId:bigint,GrossPrice:double,ItemId:bigint,ItemMajorCatId:bigint,ItemMajorCatName:string,ItemName:string,ItemPLU:bigint,ItemSubCatId:bigint,ItemSubCatName:string,OrderTime:string,ParentSequence:bigint,PosSourceId:bigint,Quantity:double,RevenueCenterId:bigint,Seat:bigint,Sequence:bigint,SoldPrice:double>>, LocationId bigint, LoyaltyId string, OpenTime string, Payments array<struct<Amount:double,EmployeeId:bigint,Gratuity:double,IsCashDebit:boolean,IsCreditCard:boolean,IsGiftCard:boolean,IsGiftCert:boolean,IsNonPOS:boolean,IsPettyCash:boolean,PayCatName:string,PayCatNo:bigint,PaymentCategoryId:bigint,PosSourceId:bigint>>, RevenueCenterId bigint, ServiceCharge bigint, TableName string, Tax array<struct<Amount:double,TaxCategoryId:bigint,TaxCategoryName:string>>, TrafficCount double, Voids array<struct<Amount:double,EmployeeId:bigint,ItemId:bigint,ItemName:string,ItemPLU:bigint,ManagerId:bigint,Quantity:double,VoidCategoryId:bigint,VoidCategoryName:string>>, _rescued_data string',
  schemaEvolutionMode => 'rescue'
);

CREATE OR REFRESH PRIVATE STREAMING TABLE raw_employees
AS SELECT *, _metadata.file_path AS _source_file,
  regexp_extract(_metadata.file_path, 'dt=([0-9-]+)', 1) AS _source_dt,
  current_timestamp() AS _ingested_at
FROM STREAM read_files(
  '${source_root}/dimensions/employees/',
  format => 'json', multiLine => false, partitionColumns => '',
  schema => 'AlternateEmployeeId string, Borrowed boolean, DateOfBirth string, Deleted boolean, HireDate string, HomeLocationId bigint, Id bigint, IsEmancipated string, IsMinor boolean, JobID array<bigint>, LocationEmployeeId string, LocationId bigint, Name string, PayrollEmployeeId string, PrimaryJobID bigint, _rescued_data string',
  schemaEvolutionMode => 'rescue'
);

CREATE OR REFRESH PRIVATE STREAMING TABLE raw_items
AS SELECT *, _metadata.file_path AS _source_file,
  regexp_extract(_metadata.file_path, 'dt=([0-9-]+)', 1) AS _source_dt,
  current_timestamp() AS _ingested_at
FROM STREAM read_files(
  '${source_root}/dimensions/items/',
  format => 'json', multiLine => false, partitionColumns => '',
  schema => 'ExternalId string, Id bigint, Name string, Plu bigint, SalesCategoryId bigint, _rescued_data string',
  schemaEvolutionMode => 'rescue'
);

CREATE OR REFRESH PRIVATE STREAMING TABLE raw_locations
AS SELECT *, _metadata.file_path AS _source_file,
  regexp_extract(_metadata.file_path, 'dt=([0-9-]+)', 1) AS _source_dt,
  current_timestamp() AS _ingested_at
FROM STREAM read_files(
  '${source_root}/dimensions/locations/',
  format => 'json', multiLine => false, partitionColumns => '',
  schema => 'ClosedDate string, Id bigint, Name string, OpenDate string, TimeZoneName string, _rescued_data string',
  schemaEvolutionMode => 'rescue'
);

CREATE OR REFRESH PRIVATE STREAMING TABLE raw_revenue_centers
AS SELECT *, _metadata.file_path AS _source_file,
  regexp_extract(_metadata.file_path, 'dt=([0-9-]+)', 1) AS _source_dt,
  current_timestamp() AS _ingested_at
FROM STREAM read_files(
  '${source_root}/dimensions/revenue_centers/',
  format => 'json', multiLine => false, partitionColumns => '',
  schema => 'Id bigint, Name string, _rescued_data string',
  schemaEvolutionMode => 'rescue'
);

