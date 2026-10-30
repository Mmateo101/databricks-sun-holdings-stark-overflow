-- Clean, isolated home for the final Applebee's silver/gold data, the discount reference
-- tables and the semantic layer used by Genie. The original catalog `workspace` is only read.

CREATE CATALOG IF NOT EXISTS applebees_semantic
  COMMENT 'Applebee''s fraud challenge (Sun Holdings x Databricks x ITESM): final silver and gold copies, discount reference data and the semantic layer for Genie. Source: workspace.applebees and workspace.applebees_gold.';

CREATE SCHEMA IF NOT EXISTS applebees_semantic.silver
  COMMENT 'Business columns of the production silver tables (copied from workspace.applebees). Lineage columns removed.';

CREATE SCHEMA IF NOT EXISTS applebees_semantic.gold
  COMMENT 'Published gold generation (copied from workspace.applebees_gold). Lineage columns removed.';

CREATE SCHEMA IF NOT EXISTS applebees_semantic.reference
  COMMENT 'Discount dictionary, official offers and promotion calendar from the team web research (Sun_Holdings_Discount_Dictionary.xlsx, Oct 16-17 2026).';

CREATE SCHEMA IF NOT EXISTS applebees_semantic.semantic
  COMMENT 'Dimensions and metric views exposed to Genie.';

CREATE VOLUME IF NOT EXISTS applebees_semantic.reference.uploads
  COMMENT 'CSV exports of the discount research workbook.';
