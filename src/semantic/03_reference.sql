-- Discount research workbook (Sun_Holdings_Discount_Dictionary.xlsx, web research of 2026-10-16/17) as tables.
-- First upload reference/*.csv to /Volumes/applebees_semantic/reference/uploads/ (tools/xlsx_to_csv.py makes them).
-- The "observed in POS data" columns of the workbook are left out: Genie computes usage from gold.

CREATE OR REPLACE TABLE applebees_semantic.reference.discount_dictionary
COMMENT 'Discount dictionary: what each POS discount code means according to web research, how reliable that is, and the restrictions documented online. Some codes have no public definition.'
AS SELECT
  CAST(discount_id AS BIGINT) AS discount_id,
  trim(pos_discount_name) AS discount_name,
  lower(level) AS discount_level,
  meaning_according_to_web_sources AS web_meaning,
  research_status,
  how_the_code_was_matched_to_the_source AS match_method,
  program_scope,
  nullif(valid_from_documented, 'Not documented') AS valid_from_documented,
  nullif(valid_to_documented, 'Not documented') AS valid_to_documented,
  nullif(specific_dates_documented, 'Not documented') AS specific_dates_documented,
  nullif(days_of_week_documented, 'Not documented') AS days_of_week_documented,
  nullif(hours_documented, 'Not documented') AS hours_documented,
  nullif(channel_documented, 'Not documented') AS channel_documented,
  nullif(minimum_spend_documented, 'Not documented') AS minimum_spend_documented,
  nullif(eligibility_documented, 'Not documented') AS eligibility_documented,
  nullif(other_conditions_documented, 'Not documented') AS other_conditions_documented,
  presence_pattern,
  weekday_concentration_index_ge1_5 AS weekday_concentration,
  daypart_concentration_index_ge1_3 AS daypart_concentration,
  `80pct_of_uses_between` AS hour_window_80pct,
  item_timing_relationship_data_web AS item_timing_notes,
  nullif(confirmed_restriction_type, '') AS confirmed_restriction_type,
  nullif(analyst_notes, '') AS analyst_notes
FROM read_files('/Volumes/applebees_semantic/reference/uploads/discount_dictionary.csv',
  format => 'csv', header => true, multiLine => true, escape => '"');
ALTER TABLE applebees_semantic.reference.discount_dictionary ALTER COLUMN discount_id COMMENT 'Discount code ID. Primary key. Same IDs as silver.discount_types (all 106 match).';
ALTER TABLE applebees_semantic.reference.discount_dictionary ALTER COLUMN discount_name COMMENT 'Discount code name as written in the POS.';
ALTER TABLE applebees_semantic.reference.discount_dictionary ALTER COLUMN discount_level COMMENT 'Where the code is used: item or check.';
ALTER TABLE applebees_semantic.reference.discount_dictionary ALTER COLUMN web_meaning COMMENT 'Meaning of the code according to internet sources only. When no source was found the text says so; meanings were not guessed from the data.';
ALTER TABLE applebees_semantic.reference.discount_dictionary ALTER COLUMN research_status COMMENT 'How well the meaning is supported: Confirmed (a source describes this exact offer), Partial (a source describes the program, term or a related offer), or Not found online (meaning open, to confirm with the client).';
ALTER TABLE applebees_semantic.reference.discount_dictionary ALTER COLUMN match_method COMMENT 'How the code was matched to the source.';
ALTER TABLE applebees_semantic.reference.discount_dictionary ALTER COLUMN program_scope COMMENT 'Scope of the program behind the code (national, Club Applebee''s loyalty, franchise or restaurant level). Not documented when no source states it.';
ALTER TABLE applebees_semantic.reference.discount_dictionary ALTER COLUMN valid_from_documented COMMENT 'Start date of the offer according to sources. NULL when not documented.';
ALTER TABLE applebees_semantic.reference.discount_dictionary ALTER COLUMN valid_to_documented COMMENT 'End date of the offer according to sources. NULL when not documented.';
ALTER TABLE applebees_semantic.reference.discount_dictionary ALTER COLUMN specific_dates_documented COMMENT 'Specific dates of the offer according to sources. NULL when not documented.';
ALTER TABLE applebees_semantic.reference.discount_dictionary ALTER COLUMN days_of_week_documented COMMENT 'Days of the week the offer is valid according to sources. NULL when not documented.';
ALTER TABLE applebees_semantic.reference.discount_dictionary ALTER COLUMN hours_documented COMMENT 'Hours the offer is valid according to sources (for example happy hour). NULL when not documented.';
ALTER TABLE applebees_semantic.reference.discount_dictionary ALTER COLUMN channel_documented COMMENT 'Channel where the offer is valid (dine-in, To Go, online). NULL when not documented.';
ALTER TABLE applebees_semantic.reference.discount_dictionary ALTER COLUMN minimum_spend_documented COMMENT 'Minimum spend required by the offer (for example 15). NULL when not documented.';
ALTER TABLE applebees_semantic.reference.discount_dictionary ALTER COLUMN eligibility_documented COMMENT 'Who can use the offer (for example Club Applebee''s members, employees, military). NULL when not documented.';
ALTER TABLE applebees_semantic.reference.discount_dictionary ALTER COLUMN other_conditions_documented COMMENT 'Other documented conditions or caps. NULL when not documented.';
ALTER TABLE applebees_semantic.reference.discount_dictionary ALTER COLUMN presence_pattern COMMENT 'When the code was used in the period: Entire period, Started or Ended mid-period, Limited window; Sporadic when used on fewer than half of the days in its span.';
ALTER TABLE applebees_semantic.reference.discount_dictionary ALTER COLUMN weekday_concentration COMMENT 'Weekdays where the code is used at least 1.5 times more than check traffic explains (for example Tue x2.3). A lead, not proof of a restriction.';
ALTER TABLE applebees_semantic.reference.discount_dictionary ALTER COLUMN daypart_concentration COMMENT 'Dayparts (Lunch 11-14h, Afternoon 14-17h, Dinner 17-21h, Late 21-02h) where the code is used at least 1.3 times more than traffic explains.';
ALTER TABLE applebees_semantic.reference.discount_dictionary ALTER COLUMN hour_window_80pct COMMENT 'Shortest clock window that contains 80 percent of the uses of the code.';
ALTER TABLE applebees_semantic.reference.discount_dictionary ALTER COLUMN item_timing_notes COMMENT 'Analyst notes relating the discounted items and timing to the web findings.';
ALTER TABLE applebees_semantic.reference.discount_dictionary ALTER COLUMN confirmed_restriction_type COMMENT 'Restriction confirmed by the team or client (empty until filled in the workbook).';
ALTER TABLE applebees_semantic.reference.discount_dictionary ALTER COLUMN analyst_notes COMMENT 'Free notes from the team or client (empty until filled in the workbook).';

CREATE OR REPLACE TABLE applebees_semantic.reference.official_offers
COMMENT 'Official 2026 Applebee''s offers (42) found by reverse search and checked against the POS data. Use to tell legitimate promotions from suspicious discount use.'
AS SELECT official_offer, official_dates, type AS offer_type, terms, match_status, how_it_shows_in_our_data AS how_it_shows_in_data,
  codes_items_used_to_match AS codes_or_items_used_to_match, source, valid_dates_documented, days_documented, hours_documented,
  channel_documented, minimum_spend_documented, eligibility_documented, caps_exclusions_documented,
  restriction_check_in_our_data AS restriction_check_in_data, restriction_sources
FROM read_files('/Volumes/applebees_semantic/reference/uploads/official_offers.csv',
  format => 'csv', header => true, multiLine => true, escape => '"');
ALTER TABLE applebees_semantic.reference.official_offers ALTER COLUMN official_offer COMMENT 'Official Applebee''s offer for 2026 (from applebees.com or Applebee''s / Dine Brands press releases).';
ALTER TABLE applebees_semantic.reference.official_offers ALTER COLUMN official_dates COMMENT 'Official dates of the offer.';
ALTER TABLE applebees_semantic.reference.official_offers ALTER COLUMN offer_type COMMENT 'Kind of offer (for example loyalty reward, limited-time menu price, gift card bonus).';
ALTER TABLE applebees_semantic.reference.official_offers ALTER COLUMN terms COMMENT 'Terms of the offer.';
ALTER TABLE applebees_semantic.reference.official_offers ALTER COLUMN match_status COMMENT 'Whether the offer was found in the POS data: Matched, Partial, Not found or Outside period.';
ALTER TABLE applebees_semantic.reference.official_offers ALTER COLUMN how_it_shows_in_data COMMENT 'How the offer appears in the POS data (discount codes, item prices).';
ALTER TABLE applebees_semantic.reference.official_offers ALTER COLUMN codes_or_items_used_to_match COMMENT 'Discount codes or items used to match the offer.';
ALTER TABLE applebees_semantic.reference.official_offers ALTER COLUMN source COMMENT 'Source URL of the offer.';
ALTER TABLE applebees_semantic.reference.official_offers ALTER COLUMN valid_dates_documented COMMENT 'Documented valid dates.';
ALTER TABLE applebees_semantic.reference.official_offers ALTER COLUMN days_documented COMMENT 'Documented valid days of the week.';
ALTER TABLE applebees_semantic.reference.official_offers ALTER COLUMN hours_documented COMMENT 'Documented valid hours.';
ALTER TABLE applebees_semantic.reference.official_offers ALTER COLUMN channel_documented COMMENT 'Documented channel (dine-in, To Go, online).';
ALTER TABLE applebees_semantic.reference.official_offers ALTER COLUMN minimum_spend_documented COMMENT 'Documented minimum spend.';
ALTER TABLE applebees_semantic.reference.official_offers ALTER COLUMN eligibility_documented COMMENT 'Documented eligibility.';
ALTER TABLE applebees_semantic.reference.official_offers ALTER COLUMN caps_exclusions_documented COMMENT 'Documented caps and exclusions.';
ALTER TABLE applebees_semantic.reference.official_offers ALTER COLUMN restriction_check_in_data COMMENT 'Result of checking the documented restrictions against the POS data (for example whether all uses meet the minimum spend).';
ALTER TABLE applebees_semantic.reference.official_offers ALTER COLUMN restriction_sources COMMENT 'Sources of the restrictions.';

CREATE OR REPLACE TABLE applebees_semantic.reference.promotion_calendar
COMMENT 'Promotions and events of the study period lined up with the discount codes and the POS data. Use to explain spikes in discount use.'
AS SELECT promotion_event, dates, scope, related_discount_codes, evidence_in_our_pos_data AS evidence_in_pos_data,
  relationship_strength, sources
FROM read_files('/Volumes/applebees_semantic/reference/uploads/promotion_calendar.csv',
  format => 'csv', header => true, multiLine => true, escape => '"');
ALTER TABLE applebees_semantic.reference.promotion_calendar ALTER COLUMN promotion_event COMMENT 'Promotion or event found online or on Facebook for the study period.';
ALTER TABLE applebees_semantic.reference.promotion_calendar ALTER COLUMN dates COMMENT 'Dates of the promotion as published.';
ALTER TABLE applebees_semantic.reference.promotion_calendar ALTER COLUMN scope COMMENT 'National or local scope.';
ALTER TABLE applebees_semantic.reference.promotion_calendar ALTER COLUMN related_discount_codes COMMENT 'Discount codes related to the promotion.';
ALTER TABLE applebees_semantic.reference.promotion_calendar ALTER COLUMN evidence_in_pos_data COMMENT 'What the POS data shows around those dates.';
ALTER TABLE applebees_semantic.reference.promotion_calendar ALTER COLUMN relationship_strength COMMENT 'How strong the link between the promotion and the data is: Strong, Partial or Weak.';
ALTER TABLE applebees_semantic.reference.promotion_calendar ALTER COLUMN sources COMMENT 'Source URLs.';

ALTER TABLE applebees_semantic.reference.discount_dictionary ALTER COLUMN discount_id SET NOT NULL;
ALTER TABLE applebees_semantic.reference.discount_dictionary ADD CONSTRAINT discount_dictionary_pk PRIMARY KEY (discount_id);
ALTER TABLE applebees_semantic.reference.discount_dictionary ADD CONSTRAINT discount_dictionary_type_fk FOREIGN KEY (discount_id) REFERENCES applebees_semantic.silver.discount_types;

ALTER TABLE applebees_semantic.reference.discount_dictionary SET TAGS ('layer' = 'reference', 'table_role' = 'dimension', 'source' = 'web_research');
ALTER TABLE applebees_semantic.reference.official_offers SET TAGS ('layer' = 'reference', 'source' = 'web_research');
ALTER TABLE applebees_semantic.reference.promotion_calendar SET TAGS ('layer' = 'reference', 'source' = 'web_research');
