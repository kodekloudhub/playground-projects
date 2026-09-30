import json
import os
import time
import uuid
from datetime import datetime, timezone
from pathlib import Path

import boto3
from confluent_kafka import Consumer

REGION = os.environ["AWS_REGION"]
BUCKET = os.environ["FINOPS_BUCKET"]
TOPIC = os.environ["KAFKA_TOPIC"]
BATCH_SECONDS = int(os.environ.get("BATCH_SECONDS", "300"))
s3 = boto3.client("s3", region_name=REGION)

def config():
    result = {
        "bootstrap.servers": os.environ["KAFKA_BOOTSTRAP_SERVERS"],
        "group.id": os.environ.get("KAFKA_GROUP_ID", "cloud-cost-pulse-consumer"),
        "auto.offset.reset": "earliest",
        "enable.auto.commit": "false",
    }
    return result

def upload(records, records_read, records_failed):
    now = datetime.now(timezone.utc)
    batch_id = now.strftime("%Y%m%dT%H%M%SZ") + "-" + uuid.uuid4().hex[:8]
    date_part = now.strftime("%Y-%m-%d")
    hour_part = now.strftime("%H")
    data_path = Path("/tmp") / f"{batch_id}.jsonl"
    manifest_path = Path("/tmp") / f"{batch_id}.json"
    data_path.write_text("\n".join(json.dumps(r) for r in records) + ("\n" if records else ""))
    prefix = f"raw/events/dt={date_part}/hour={hour_part}"
    upload_started = time.monotonic()
    s3.upload_file(str(data_path), BUCKET, f"{prefix}/{batch_id}.jsonl")
    batch_upload_seconds = round(time.monotonic() - upload_started, 3)
    manifest = {
        "batch_id": batch_id,
        "row_count": len(records),
        "records_read": records_read,
        "records_failed": records_failed,
        "batch_upload_seconds": batch_upload_seconds,
        "created_at": now.isoformat(),
    }
    manifest_path.write_text(json.dumps(manifest))
    s3.upload_file(str(manifest_path), BUCKET, f"raw/manifests/{batch_id}.json")
    data_path.unlink(missing_ok=True)
    manifest_path.unlink(missing_ok=True)
    return batch_id, batch_upload_seconds

def main():
    consumer = Consumer(config())
    consumer.subscribe([TOPIC])
    records = []
    records_read = 0
    records_failed = 0
    started = time.monotonic()
    try:
        while True:
            message = consumer.poll(1.0)
            if message is not None and message.error():
                records_failed += 1
            elif message is not None:
                records_read += 1
                try:
                    records.append(json.loads(message.value().decode("utf-8")))
                except (UnicodeDecodeError, json.JSONDecodeError):
                    records_failed += 1
                    records.append({"raw_payload": message.value().decode("utf-8", errors="replace")})
            if (records or records_failed) and time.monotonic() - started >= BATCH_SECONDS:
                batch_id, batch_upload_seconds = upload(records, records_read, records_failed)
                print(json.dumps({"batch_id": batch_id, "records_read": records_read,
                                  "records_failed": records_failed,
                                  "batch_upload_seconds": batch_upload_seconds}), flush=True)
                consumer.commit(asynchronous=False)
                records = []
                records_read = 0
                records_failed = 0
                started = time.monotonic()
    finally:
        consumer.close()

if __name__ == "__main__":
    main()
