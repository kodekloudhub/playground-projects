import json, os, time, uuid
from datetime import datetime, timezone
from decimal import Decimal, InvalidOperation
import boto3
from _common import db_conn, load_state, log_done, save_state

started=time.monotonic(); state=load_state(); batch=state["batch_id"]; region=os.environ["AWS_REGION"]; bucket=os.environ["FINOPS_BUCKET"]
s3=boto3.client("s3", region_name=region); raw=s3.get_object(Bucket=bucket,Key=state["event_key"])["Body"].read().decode()
required=("event_id","event_time","received_at","team","service","environment","region","customer_id","usage_type","unit","quantity","schema_version")
pairs={"request":"requests","storage":"GB-hours","egress":"GB"}; supported={"1.0"}
valid=[]; issues=[]; seen=set()
def reject(record,eid,kind,detail):
    qkey=f"quarantine/events/batch_id={batch}/{eid or uuid.uuid4().hex}.json"
    s3.put_object(Bucket=bucket,Key=qkey,Body=(json.dumps(record)+"\n").encode(),ContentType="application/json")
    issues.append((eid,kind,detail))
for line_no,line in enumerate(raw.splitlines(),1):
    try: record=json.loads(line)
    except json.JSONDecodeError as e:
        reject({"raw_payload":line},None,"invalid_json",f"line {line_no}: {e.msg}"); continue
    if not isinstance(record, dict):
        reject({"raw_payload":line},None,"invalid_record","JSON event must be an object"); continue
    eid=str(record.get("event_id","")).strip()
    if eid in seen:
        reject(record,eid,"duplicate_event_id","duplicate within batch"); continue
    seen.add(eid)
    try:
        missing=[k for k in required if record.get(k) in (None,"")]
        if missing: raise ValueError("missing: "+", ".join(missing))
        for k in ("event_time","received_at"):
            dt=datetime.fromisoformat(str(record[k]).replace("Z","+00:00"))
            if dt.tzinfo is None: raise ValueError(f"{k} must include UTC timezone")
            record[k]=dt.astimezone(timezone.utc).isoformat()
        quantity=Decimal(str(record["quantity"]))
        if quantity < 0: raise ValueError("quantity must be non-negative")
        if pairs.get(record["usage_type"]) != record["unit"]: raise ValueError("usage_type/unit pair is unsupported")
        if record["schema_version"] not in supported: raise ValueError("unsupported schema_version")
        record["batch_id"]=batch; valid.append(record)
    except (ValueError,InvalidOperation,TypeError) as e:
        reject(record,eid,"validation_error",str(e))
conn=db_conn()
with conn:
    with conn.cursor() as cur:
        cur.executemany("""insert into audit.data_quality_issues(batch_id,event_id,issue_type,issue_detail) values (%s,%s,%s,%s)""",[(batch,eid,k,d) for eid,k,d in issues])
conn.close()
valid_path=f"/tmp/cloud-cost-pulse-valid-{batch}.jsonl"; Path(valid_path).write_text("\n".join(json.dumps(r) for r in valid)+("\n" if valid else ""))
state.update({"valid_path":valid_path,"valid_count":len(valid),"issue_count":len(issues)}) ; save_state(state)
log_done("validate_batch",batch,started,state.get("row_count",0),len(valid),f"quarantine/events/batch_id={batch}/",["audit.data_quality_issues"])
