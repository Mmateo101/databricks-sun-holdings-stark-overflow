# Reproduce locally or in an authorized Databricks workspace

## Local synthetic demonstration

Use Python 3.12. Install `requirements.txt`, run the unit tests, then `python demo/run_demo.py`. Open `demo/model-demo.html` directly or serve this repository with `python -m http.server 8000`. All observations are generated in code from a fixed seed; no data export is needed. The plots load D3 7.9.0 from a pinned public CDN, so displaying them requires internet access. Numerical generation/tests use no data services.

## Databricks prerequisites

- A current Databricks CLI and an authenticated local profile. Host/profile/token configuration remains outside Git.
- Unity Catalog access to an authorized POS JSONL volume and permission to create the dedicated output schemas and serverless resources. Create/select the configured target catalog first; the model does not silently adopt foreign outputs.
- Expected source directories: `checks/`, `dimensions/employees/`, `dimensions/items/`, `dimensions/locations/`, `dimensions/revenue_centers/`. See the explicit JSON schemas in the Silver SQL. Raw data and company reference workbooks are not distributed here.
- At least five full Thursday weeks and sufficient interior activity counts to fit the model's four-week background and score later observations. The review pilot requires enough informed cases for its declared budget.

Set variables with environment variables or an ignored `databricks.local.yml`/CLI override. For example:

```bash
databricks auth login --profile YOUR_PROFILE
databricks bundle validate --profile YOUR_PROFILE --var source_root=/Volumes/YOUR_CATALOG/YOUR_SCHEMA/YOUR_VOLUME
databricks bundle plan --profile YOUR_PROFILE --var source_root=/Volumes/YOUR_CATALOG/YOUR_SCHEMA/YOUR_VOLUME
```

Review the plan and choose dedicated `silver_schema`, `gold_schema` prefix and `model_schema` values. The defaults use the authenticated user's short name for Silver/model namespaces. `catalog` defaults to `applebees_semantic`; `source_catalog` defaults to `workspace`. Override them for your workspace. `expected_owner` and the deployed code root are supplied by bundle substitutions; no individual identity is hardcoded.

Only after reviewing the resource plan:

```bash
databricks bundle deploy --profile YOUR_PROFILE --var source_root=/Volumes/YOUR_CATALOG/YOUR_SCHEMA/YOUR_VOLUME
databricks bundle run weekly_model --profile YOUR_PROFILE --var source_root=/Volumes/YOUR_CATALOG/YOUR_SCHEMA/YOUR_VOLUME
```

The Job has no schedule. Its tasks refresh Silver, snapshot isolated Gold, prepare discount-actor weeks and fit/score the scenarios. Inspect the task's completion output rather than treating submission as success. Keep Silver stable while Gold copies are made. Gold task values supply the new source table names to actor preparation. Retained run schemas are not automatically removed.

The public portable wrappers are a parameterized adaptation of the executed development workflow. Bundle schema validation and local tests do not prove a fresh deployment's runtime permissions, source retention or successful execution. Run and inspect it in an authorized development workspace before production use. This submission does not redeploy or modify the team's existing live resources.

## Review and view

Use the successful model Job run identifier as `review_model_run_id`:

```bash
databricks bundle run review_pilot --profile YOUR_PROFILE --var source_root=/Volumes/YOUR_CATALOG/YOUR_SCHEMA/YOUR_VOLUME --var review_model_run_id=COMPLETED_MODEL_RUN
```

The review Job returns the new `review_batch_id` in its result. Open the deployed review notebook interactively for independent decisions. See [review protocol](review-protocol.md). `src/models/view_employee.py` reads one completed model run with configurable employee/location selectors.

## Existing team semantic SQL and Genie

The team's semantic scripts retain their order and definitions. Namespace literals are now parameters. `src/transformations/run_sql.py --dry-run` validates substitutions without credentials or remote requests. For the copy layer, explicitly choose its source namespaces:

```bash
python src/transformations/run_sql.py src/transformations/gold/semantic/00_catalog.sql src/transformations/gold/semantic/01_silver_copy.sql src/transformations/gold/semantic/02_gold_copy.sql --dry-run --var catalog=YOUR_TARGET_CATALOG --var source_silver_schema=YOUR_SOURCE_CATALOG.YOUR_SILVER_SCHEMA --var source_gold_schema=YOUR_TARGET_CATALOG.YOUR_GOLD_RUN_SCHEMA
```

For a live SQL run, set `DATABRICKS_WAREHOUSE_ID` and omit `--dry-run`; use `--profile YOUR_PROFILE` if needed. The Gold namespace must expose `gold_check_facts`, `gold_discount_events`, `gold_location_day` and one `gold_publication` row at slot 1. The isolated Gold task returns its namespace. Existing team production publication views can also satisfy this contract. Gold generation lookup is disabled during dry runs.

Reference data remains an authorized external prerequisite for `03_reference.sql`; upload its CSVs to the configured catalog's `reference.uploads` volume. The old reference comment mentioning an XLSX conversion helper does not ship that helper. Apply `04`–`06`, then the existing fraud-feature day/week scripts with explicit `source`/`target` variables, the fraud comments and `gold/semantic/07_fraud.sql` as documented in the README. These scripts use CREATE OR REPLACE and alter schema metadata: run them only against the intended team-owned target.

Set `DATABRICKS_CATALOG` before using `src/transformations/gold/semantic/genie_space.py`; it defaults to the logical catalog name `applebees_semantic`. Genie validation uses the configured warehouse. The original semantic/Genie contributions are preserved; the weekly model does not require copying or rewriting them to score its isolated inputs.
