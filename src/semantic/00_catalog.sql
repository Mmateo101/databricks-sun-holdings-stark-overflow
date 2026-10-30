-- Clean, isolated home for the final Applebee's silver/gold data, the discount reference
-- tables and the semantic layer used by Genie. The original catalog `workspace` is only read.

CREATE CATALOG IF NOT EXISTS ${catalog}
  COMMENT 'Applebee''s fraud challenge (Sun Holdings x Databricks x ITESM): final silver and gold copies, discount reference data and the semantic layer for Genie. Source: ${source_silver_schema} and ${source_gold_schema}.';

CREATE SCHEMA IF NOT EXISTS ${catalog}.silver
  COMMENT 'Business columns of the production silver tables (copied from ${source_silver_schema}). Lineage columns removed.';

CREATE SCHEMA IF NOT EXISTS ${catalog}.gold
  COMMENT 'Published gold generation (copied from ${source_gold_schema}). Lineage columns removed.';

CREATE SCHEMA IF NOT EXISTS ${catalog}.reference
  COMMENT 'Discount dictionary, official offers and promotion calendar from the team web research (Sun_Holdings_Discount_Dictionary.xlsx, Oct 16-17 2026).';

CREATE SCHEMA IF NOT EXISTS ${catalog}.semantic
  COMMENT 'Dimensions and metric views exposed to Genie.';

CREATE VOLUME IF NOT EXISTS ${catalog}.reference.uploads
  COMMENT 'CSV exports of the discount research workbook.';
