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

def upload(records):
    now = datetime.now(timezone.utc)
    batch_id = now.strftime("%Y%m%dT%H%M%SZ") + "-" + uuid.uuid4().hex[:8]
    date_part = now.strftime("%Y-%m-%d")
    hour_part = now.strftime("%H")
    data_path = Path("/tmp") / f"{batch_id}.jsonl"
    manifest_path = Path("/tmp") / f"{batch_id}.json"
    data_path.write_text("\n".join(json.dumps(r) for r in records) + "\n")
    manifest_path.write_text(json.dumps({"batch_id": batch_id, "row_count": len(records), "created_at": now.isoformat()}))
    prefix = f"raw/events/dt={date_part}/hour={hour_part}"
    s3.upload_file(str(data_path), BUCKET, f"{prefix}/{batch_id}.jsonl")
    s3.upload_file(str(manifest_path), BUCKET, f"raw/manifests/{batch_id}.json")
    data_path.unlink(missing_ok=True)
    manifest_path.unlink(missing_ok=True)
    return batch_id

def main():
    consumer = Consumer(config())
    consumer.subscribe([TOPIC])
    records = []
    started = time.monotonic()
    try:
        while True:
            message = consumer.poll(1.0)
            if message and not message.error():
                try:
                    records.append(json.loads(message.value().decode("utf-8")))
                except json.JSONDecodeError:
                    records.append({"raw_payload": message.value().decode("utf-8", errors="replace")})
            if records and time.monotonic() - started >= BATCH_SECONDS:
                print(f"uploading rows={len(records)}", flush=True)
                print(upload(records), flush=True)
                consumer.commit(asynchronous=False)
                records = []
                started = time.monotonic()
    finally:
        consumer.close()

if __name__ == "__main__":
    main()
