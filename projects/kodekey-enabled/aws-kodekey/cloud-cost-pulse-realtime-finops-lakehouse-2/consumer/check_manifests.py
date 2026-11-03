import json, os, time
from pathlib import Path
import boto3
from _common import save_state

started = time.monotonic(); region = os.environ["AWS_REGION"]; bucket = os.environ["FINOPS_BUCKET"]
s3 = boto3.client("s3", region_name=region)
manifest_keys = []
for page in s3.get_paginator("list_objects_v2").paginate(Bucket=bucket, Prefix="raw/manifests/"):
    manifest_keys.extend(o["Key"] for o in page.get("Contents", []))
if not manifest_keys:
    raise RuntimeError("no raw manifest found")
key = sorted(manifest_keys)[-1]
manifest = json.loads(s3.get_object(Bucket=bucket, Key=key)["Body"].read())
batch_id = manifest["batch_id"]
event_key = None
for page in s3.get_paginator("list_objects_v2").paginate(Bucket=bucket, Prefix="raw/events/"):
    for obj in page.get("Contents", []):
        if obj["Key"].endswith(f"/{batch_id}.jsonl"):
            event_key = obj["Key"]; break
    if event_key: break
if not event_key:
    raise RuntimeError(f"event object not found for batch {batch_id}")
save_state({"batch_id": batch_id, "manifest_key": key, "event_key": event_key,
            "row_count": manifest["row_count"], "records_read": manifest["records_read"],
            "records_failed": manifest["records_failed"],
            "batch_upload_seconds": manifest["batch_upload_seconds"]})
print(json.dumps({"dag_id": os.environ.get("AIRFLOW_CTX_DAG_ID", "finops_microbatch"),
  "task_id": os.environ.get("AIRFLOW_CTX_TASK_ID", "check_new_manifests"),
  "run_id": os.environ.get("AIRFLOW_CTX_RUN_ID", "manual"), "batch_id":batch_id,
  "input_row_count":manifest.get("row_count",0), "output_row_count":1,
  "affected_s3_prefix":"raw/manifests/", "database_tables":[],
  "elapsed_seconds":round(time.monotonic()-started,3)}), flush=True)
