select event_id, rate_card_id, model_run_id, estimated_cost
from analytics.fact_cost
where event_id = 'REPLACE_WITH_REPLAYED_EVENT_ID'
order by loaded_at, rate_card_id;
