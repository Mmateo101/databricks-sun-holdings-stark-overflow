"""SQL helper: runs on Databricks (spark) if available, otherwise on the SQL warehouse via the SDK."""
import io, os, time, urllib.request
import pandas as pd

PROFILE = os.environ.get("DATABRICKS_CONFIG_PROFILE", "DEFAULT")
WAREHOUSE_ID = os.environ.get("DATABRICKS_WAREHOUSE_ID", "")
_w = None


def sql(query: str) -> pd.DataFrame:
    try:
        from pyspark.sql import SparkSession  # inside Databricks
        spark = SparkSession.getActiveSession()
        if spark is not None:
            return spark.sql(query).toPandas()
    except ImportError:
        pass
    import pyarrow as pa
    from databricks.sdk import WorkspaceClient
    from databricks.sdk.service.sql import Disposition, Format, StatementState
    global _w
    if not WAREHOUSE_ID:
        raise SystemExit('Set DATABRICKS_WAREHOUSE_ID (and DATABRICKS_CONFIG_PROFILE if not DEFAULT)')
    _w = _w or WorkspaceClient(profile=PROFILE)
    r = _w.statement_execution.execute_statement(warehouse_id=WAREHOUSE_ID, statement=query, wait_timeout="50s",
                                                 disposition=Disposition.EXTERNAL_LINKS, format=Format.ARROW_STREAM)
    while r.status.state in (StatementState.PENDING, StatementState.RUNNING):
        time.sleep(2)
        r = _w.statement_execution.get_statement(r.statement_id)
    if r.status.state != StatementState.SUCCEEDED:
        raise RuntimeError(r.status.error.message if r.status.error else r.status.state)
    tables, chunk = [], r.result
    while chunk is not None:
        for link in chunk.external_links or []:
            with urllib.request.urlopen(link.external_link) as f:
                tables.append(pa.ipc.open_stream(io.BytesIO(f.read())).read_all())
        nxt = chunk.next_chunk_index if chunk.external_links else None
        chunk = _w.statement_execution.get_statement_result_chunk_n(r.statement_id, nxt) if nxt is not None else None
    if not tables:
        return pd.DataFrame(columns=[c.name for c in r.manifest.schema.columns])
    return pa.concat_tables(tables).to_pandas()
