select
  event_id,
  event_time,
  received_at,
  nullif(trim(team),'') as team,
  nullif(trim(service),'') as service,
  environment,
  region,
  customer_id,
  usage_type,
  quantity,
  unit,
  schema_version,
  batch_id
from staging.usage_events
where quantity >= 0
