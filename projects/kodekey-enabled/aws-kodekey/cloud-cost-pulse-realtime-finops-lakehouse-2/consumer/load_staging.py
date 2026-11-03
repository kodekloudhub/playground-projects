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
