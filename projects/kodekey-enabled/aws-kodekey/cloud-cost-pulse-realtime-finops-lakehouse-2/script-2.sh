cat > consumer/_common.py <<'PY'
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
PY

cat > consumer/check_manifests.py <<'PY'
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
PY

cat > consumer/validate_batch.py <<'PY'
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
PY

cat > consumer/load_staging.py <<'PY'
import json, time
from _common import db_conn, load_state, log_done, save_state
started=time.monotonic(); state=load_state(); batch=state["batch_id"]
rows=[json.loads(x) for x in open(state["valid_path"]) if x.strip()]; loaded=duplicates=0
conn=db_conn()
with conn:
    with conn.cursor() as cur:
        for r in rows:
            cur.execute("""insert into staging.usage_events(event_id,event_time,received_at,team,service,environment,region,customer_id,usage_type,quantity,unit,schema_version,batch_id) values (%(event_id)s,%(event_time)s,%(received_at)s,%(team)s,%(service)s,%(environment)s,%(region)s,%(customer_id)s,%(usage_type)s,%(quantity)s,%(unit)s,%(schema_version)s,%(batch_id)s) on conflict (event_id) do nothing""",r)
            if cur.rowcount: loaded+=1
            else:
                duplicates+=1
                cur.execute("insert into audit.data_quality_issues(batch_id,event_id,issue_type,issue_detail) values (%s,%s,%s,%s)",(batch,r["event_id"],"duplicate_event_id","already present in staging"))
conn.close(); state.update({"loaded_count":loaded,"duplicate_count":duplicates}); save_state(state)
log_done("load_staging",batch,started,len(rows),loaded,"raw/events/",["staging.usage_events","audit.data_quality_issues"])
PY

cat > consumer/detect_anomalies.py <<'PY'
import hashlib, os, time
from datetime import timedelta
from decimal import Decimal
from _common import db_conn, log_done
started=time.monotonic(); conn=db_conn(); conn.autocommit=False
with conn:
    with conn.cursor() as cur:
        cur.execute("""with current_cost as (select distinct on (event_id) event_id,event_time,team,service,environment,region,estimated_cost from analytics.fact_cost order by event_id,loaded_at desc,model_run_id desc) select concat_ws(':',coalesce(team,''),coalesce(service,''),environment,region) scope_id, date_trunc('hour',event_time)+floor(extract(minute from event_time)/5)*interval '5 minutes' window_start, sum(estimated_cost) cost from current_cost group by 1,2 order by 2""")
        rows=cur.fetchall()
        if rows:
            current=max(r[1] for r in rows); current_rows=[r for r in rows if r[1]==current]
            for scope,window,observed in current_rows:
                history=[r[2] for r in rows if r[0]==scope and current-timedelta(days=7)<=r[1]<current and r[1].hour==window.hour and (r[1].minute//5)==(window.minute//5)]
                if len(history)<3:
                    print(f"no anomaly scope={scope} window={window.isoformat()} reason=insufficient comparable history count={len(history)}",flush=True); continue
                baseline=sum(history,Decimal("0"))/Decimal(len(history)); absolute=Decimal(observed)-baseline; pct=(absolute/baseline*100) if baseline else Decimal("999999")
                if pct < 50 or absolute < 5: continue
                severity="critical" if pct>=200 else "warning"; evidence=f"{window.isoformat()}/{(window+timedelta(minutes=5)).isoformat()}"; anomaly=hashlib.sha256(f"{scope}|{evidence}".encode()).hexdigest()[:32]
                cur.execute("""insert into analytics.fact_anomaly(anomaly_id,detected_at,scope_id,baseline_cost,observed_cost,absolute_delta,percentage_delta,detection_method,severity,evidence_window,detector_version) values (%s,now(),%s,%s,%s,%s,%s,'five_minute_baseline',%s,%s,'v1') on conflict (anomaly_id) do nothing""",(anomaly,scope,baseline,observed,absolute,pct,severity,evidence))
conn.close(); log_done("detect_anomalies","latest",started,len(rows),0,"analytics.fact_cost",["analytics.fact_cost","analytics.fact_anomaly"])
PY

cat > consumer/explain_anomalies.py <<'PY'
import json, os, time
from datetime import datetime, timezone
from _common import db_conn, log_done
from kodekey_provider import explain, get_secret
started=time.monotonic(); secret=get_secret(os.environ["KODEKEY_SECRET_ID"])
conn=db_conn(); processed=0
with conn:
    with conn.cursor() as cur:
        cur.execute("""select a.anomaly_id,a.scope_id,a.baseline_cost,a.observed_cost,a.percentage_delta,a.evidence_window,a.detector_version from analytics.fact_anomaly a where a.status='open' and not exists (select 1 from audit.ai_explanations x where x.anomaly_id=a.anomaly_id and x.status='succeeded')""")
        for row in cur.fetchall():
            anomaly={"anomaly_id":row[0],"scope_id":row[1],"baseline_cost":str(row[2]),"observed_cost":str(row[3]),"percentage_delta":str(row[4]),"evidence_window":row[5],"detector_version":row[6]}
            status="succeeded"; response_payload=None; payload=None
            try:
                payload,response_payload=explain(anomaly,secret)
            except Exception as e:
                status="failed"; response_payload={"error":str(e)}
            cur.execute("""insert into audit.ai_explanations(anomaly_id,model_name,prompt_version,request_payload,response_payload,status,requested_at,completed_at) values (%s,%s,%s,%s::jsonb,%s::jsonb,%s,%s,%s)""",(row[0],secret["model"],"v1",json.dumps(payload),json.dumps(response_payload) if response_payload is not None else None,status,datetime.now(timezone.utc),datetime.now(timezone.utc))); processed+=1
conn.close(); log_done("explain_anomalies", "latest", started, processed, processed, "", ["analytics.fact_anomaly","audit.ai_explanations"])
PY

cat > consumer/publish_metrics.py <<'PY'
import os, time
import boto3
from _common import db_conn, load_state, log_done
started=time.monotonic(); state=load_state(); batch=state["batch_id"]; region=os.environ["AWS_REGION"]; env=os.environ.get("ENVIRONMENT","production")
records_read=int(state["records_read"])
records_failed=int(state["records_failed"])
batch_upload_seconds=float(state["batch_upload_seconds"])
conn=db_conn()
with conn.cursor() as cur:
    cur.execute("select count(*) from staging.usage_events where batch_id=%s",(batch,)); loaded=cur.fetchone()[0]
    cur.execute("select count(*) from audit.data_quality_issues where batch_id=%s",(batch,)); quarantined=cur.fetchone()[0]
    cur.execute("select count(*) from analytics.fact_anomaly where status='open'"); open_count=cur.fetchone()[0]
    cur.execute("select count(*) from audit.ai_explanations where requested_at >= now()-interval '15 minutes'"); requests_count=cur.fetchone()[0]
    cur.execute("select count(*) from audit.ai_explanations where status='failed' and requested_at >= now()-interval '15 minutes'"); failures=cur.fetchone()[0]
    cur.execute("select extract(epoch from (now()-max(loaded_at))) from staging.usage_events"); freshness=cur.fetchone()[0] or 0
conn.close()
dims=[{"Name":"Environment","Value":env},{"Name":"Region","Value":region}]
data=[]
metrics=[
    ("consumer.records_read",records_read,"Count"),
    ("consumer.records_failed",records_failed,"Count"),
    ("consumer.batch_upload_seconds",batch_upload_seconds,"Seconds"),
    ("pipeline.rows_loaded",loaded,"Count"),
    ("pipeline.rows_quarantined",quarantined,"Count"),
    ("pipeline.freshness_seconds",float(freshness),"Seconds"),
    ("anomaly.open_count",open_count,"Count"),
    ("kodekey.request_count",requests_count,"Count"),
    ("kodekey.failure_count",failures,"Count"),
]
for name,value,unit in metrics:
    data.append({"MetricName":name,"Dimensions":dims,"Value":value,"Unit":unit})
boto3.client("cloudwatch",region_name=region).put_metric_data(Namespace="CloudCostPulse",MetricData=data)
log_done("publish_metrics",batch,started,loaded,len(data),"",["staging.usage_events","audit.data_quality_issues","analytics.fact_anomaly","audit.ai_explanations"])
PY

python -m py_compile consumer/consumer.py consumer/_common.py consumer/check_manifests.py consumer/validate_batch.py consumer/load_staging.py consumer/detect_anomalies.py consumer/explain_anomalies.py consumer/publish_metrics.py
