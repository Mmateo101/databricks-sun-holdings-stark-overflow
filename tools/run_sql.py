"""Run SQL scripts statement by statement on the SQL warehouse through the Databricks CLI.

Usage: DATABRICKS_WAREHOUSE_ID=<id> python3 tools/run_sql.py src/semantic/00_catalog.sql [...] [--dry-run]
Statements end with ';' at the end of a line. '--' lines are dropped. ${generation_id} is replaced
with the generation currently published in workspace.applebees_gold.gold_publication (slot 1).
Other ${name} placeholders take --var name=value (for example --var target=applebees_semantic.gold.fraud_employee_day).
"""
import json
import os
import re
import subprocess
import sys
import time

WAREHOUSE_ID = os.environ["DATABRICKS_WAREHOUSE_ID"]  # set it in your shell, never commit it


def api(method, path, body=None):
    cmd = ["databricks", "api", method, path]
    if body is not None:
        cmd += ["--json", json.dumps(body)]
    out = subprocess.run(cmd, capture_output=True, text=True, check=True).stdout
    return json.loads(out)


def execute(sql):
    r = api("post", "/api/2.0/sql/statements",
            {"warehouse_id": WAREHOUSE_ID, "statement": sql, "wait_timeout": "50s",
             "on_wait_timeout": "CONTINUE"})
    while r["status"]["state"] in ("PENDING", "RUNNING"):
        time.sleep(5)
        r = api("get", f"/api/2.0/sql/statements/{r['statement_id']}")
    if r["status"]["state"] != "SUCCEEDED":
        raise RuntimeError(r["status"].get("error", {}).get("message", r["status"]["state"]))
    return r.get("result", {}).get("data_array") or []


def statements(path):
    text = "\n".join(l for l in open(path, encoding="utf-8").read().splitlines()
                     if not l.lstrip().startswith("--"))
    return [s.strip() for s in re.split(r";\s*\n", text + "\n") if s.strip()]


def main(paths, dry_run, variables):
    generation_id = None
    for path in paths:
        for i, sql in enumerate(statements(path), 1):
            if "${generation_id}" in sql:
                if generation_id is None:
                    generation_id = execute("SELECT generation_id FROM workspace.applebees_gold.gold_publication WHERE slot = 1")[0][0]
                sql = sql.replace("${generation_id}", generation_id)
            for name, value in variables.items():
                sql = sql.replace("${" + name + "}", value)
            label = f"{path} #{i}: {' '.join(sql.split())[:90]}"
            if dry_run:
                print("DRY", label)
                continue
            t = time.time()
            execute(sql)
            print(f"OK  {label}  ({time.time() - t:.0f}s)", flush=True)


if __name__ == "__main__":
    args = sys.argv[1:]
    variables = dict(args[i + 1].split("=", 1) for i, a in enumerate(args) if a == "--var")
    paths = [a for i, a in enumerate(args) if a not in ("--dry-run", "--var") and (i == 0 or args[i - 1] != "--var")]
    main(paths, "--dry-run" in args, variables)
