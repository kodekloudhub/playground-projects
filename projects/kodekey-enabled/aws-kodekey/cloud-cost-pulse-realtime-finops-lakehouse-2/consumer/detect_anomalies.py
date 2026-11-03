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
