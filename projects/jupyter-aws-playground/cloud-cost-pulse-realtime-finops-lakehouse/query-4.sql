select
  u.event_id,
  u.event_time,
  u.team,
  u.service,
  u.environment,
  u.region,
  u.customer_id,
  u.usage_type,
  u.quantity,
  u.unit,
  r.price_per_unit,
  u.quantity * r.price_per_unit as estimated_cost,
  u.batch_id,
  md5(u.batch_id || ':' || u.event_id) as model_run_id
from {{ ref('stg_usage_events') }} u
join staging.rate_cards r
  on r.usage_type = u.usage_type
 and r.unit = u.unit
 and r.region = u.region
 and u.event_time >= r.effective_from
 and (r.effective_to is null or u.event_time < r.effective_to)
