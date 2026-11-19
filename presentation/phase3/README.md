# Phase 3 presentation

The final Phase 3 deck (Proposed Solution). It is one HTML page with GSAP animations. `build.py` puts the template, the data, the fonts and the logos into a single file, `dist/index.html`, that can be opened locally or deployed as is.

**No data is committed here.** The numbers the deck shows (`data.json`, `redes.json`) are generated from Databricks and stay out of the repo (see `.gitignore`).

## Files

| File | What it is |
|---|---|
| `template.html` | The slides: styles, scenes and animations. This is the file to edit |
| `build.py` | Builds `dist/index.html` from the template, the data, the fonts, GSAP and the logos |
| `export_data.py` | Read-only queries on `applebees_semantic` that write `data.json`. Employees and restaurants are anonymized (Employee A, Restaurant 1) |
| `queries.py`, `dbx.py` | SQL used by the export and a small helper that runs it on a SQL warehouse |
| `assets/` | Fonts (Fraunces, Nunito, Caveat), GSAP and the three logos |

## How to build it

1. Get the data. Ask a teammate for `data.json` and `redes.json`, or generate `data.json` yourself:
   ```bash
   pip install databricks-sdk pandas pyarrow scipy numpy
   export DATABRICKS_CONFIG_PROFILE=<your CLI profile>
   export DATABRICKS_WAREHOUSE_ID=<SQL warehouse id>
   export DECK_MODEL_SCHEMA=applebees_semantic.<model schema>
   export DECK_SHOWCASE_EMPLOYEE_ID=<employee shown as "Employee A">
   python export_data.py
   ```
   `redes.json` comes from the Bayesian networks notebook (statistical tests). Put both files in this folder.
2. Build:
   ```bash
   python build.py
   ```
3. Open `dist/index.html` in Chrome. Space or → moves forward, ← goes back, F is full screen.

## How to edit it

- Each scene is a `scene({ build, reset, steps })` block in `template.html`. `build` creates the elements, `reset` puts them in their starting state, and every function in `steps` is one click.
- After any change, run `python build.py` again and reload the page.
- To jump to a step while editing, open the console and run `__deck.go(n)` (0-based), or add `#n` to the URL.

## Deploy

`dist/` is a static site. With the Vercel CLI: `cd dist && vercel --prod`.
