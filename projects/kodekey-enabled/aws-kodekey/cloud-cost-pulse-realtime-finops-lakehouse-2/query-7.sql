select anomaly_id, scope_id, baseline_cost, observed_cost, percentage_delta, severity
from analytics.fact_anomaly
order by detected_at desc;

select anomaly_id, model_name, prompt_version, status, requested_at, completed_at
from audit.ai_explanations
order by requested_at desc;
