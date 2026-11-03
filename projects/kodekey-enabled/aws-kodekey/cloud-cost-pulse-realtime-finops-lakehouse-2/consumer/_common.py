import json
import os
from pathlib import Path
import boto3
import psycopg2

STATE = Path(os.environ.get("BATCH_STATE_FILE", "/tmp/cloud-cost-pulse-batch.json"))

def load_state():
    if not STATE.exists():
        raise RuntimeError(f"missing batch state: {STATE}")
    return json.loads(STATE.read_text())

def save_state(state):
    STATE.write_text(json.dumps(state))

def db_secret():
    sm = boto3.client("secretsmanager", region_name=os.environ["AWS_REGION"])
    return json.loads(sm.get_secret_value(SecretId=os.environ["DB_SECRET_ID"])["SecretString"])

def db_conn():
    s = db_secret()
    return psycopg2.connect(
        host=s["host"], port=s.get("port", 5432), user=s["username"],
        password=s["password"], dbname=s.get("finops_database", "finops"),
        sslmode="require",
    )

def log_done(task, batch_id, started, input_rows, output_rows, prefix, tables):
    import time
    print(json.dumps({"dag_id": os.environ.get("AIRFLOW_CTX_DAG_ID", "finops_microbatch"),
      "task_id": os.environ.get("AIRFLOW_CTX_TASK_ID", task),
      "run_id": os.environ.get("AIRFLOW_CTX_RUN_ID", "manual"), "batch_id": batch_id,
      "input_row_count": input_rows, "output_row_count": output_rows,
      "affected_s3_prefix": prefix, "database_tables": tables,
      "elapsed_seconds": round(time.monotonic() - started, 3)}), flush=True)
