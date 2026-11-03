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
