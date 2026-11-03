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
