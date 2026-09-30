create schema if not exists staging;
create schema if not exists analytics;
create schema if not exists audit;

create table if not exists staging.usage_events (
  event_id text primary key,
  event_time timestamptz not null,
  received_at timestamptz not null,
  team text,
  service text,
  environment text,
  region text,
  customer_id text,
  usage_type text,
  quantity numeric,
  unit text,
  schema_version text,
  batch_id text not null,
  loaded_at timestamptz not null default now()
);

create table if not exists staging.rate_cards (
  rate_card_id text primary key,
  usage_type text not null,
  unit text not null,
  region text not null,
  price_per_unit numeric not null,
  effective_from timestamptz not null,
  effective_to timestamptz
);

create table if not exists analytics.fact_cost (
  event_id text primary key,
  event_time timestamptz not null,
  team text,
  service text,
  environment text,
  region text,
  customer_id text,
  usage_type text,
  quantity numeric not null,
  unit text not null,
  price_per_unit numeric not null,
  estimated_cost numeric not null,
  batch_id text not null,
  model_run_id text not null,
  loaded_at timestamptz not null default now()
);

create table if not exists analytics.fact_anomaly (
  anomaly_id text primary key,
  detected_at timestamptz not null,
  scope_id text not null,
  baseline_cost numeric not null,
  observed_cost numeric not null,
  absolute_delta numeric not null,
  percentage_delta numeric not null,
  detection_method text not null,
  severity text not null,
  evidence_window text not null,
  detector_version text not null,
  status text not null default 'open'
);

create table if not exists audit.data_quality_issues (
  issue_id bigserial primary key,
  batch_id text not null,
  event_id text,
  issue_type text not null,
  issue_detail text not null,
  created_at timestamptz not null default now()
);

create table if not exists audit.ai_explanations (
  explanation_id bigserial primary key,
  anomaly_id text not null,
  model_name text not null,
  prompt_version text not null,
  request_payload jsonb not null,
  response_payload jsonb,
  status text not null,
  requested_at timestamptz not null default now(),
  completed_at timestamptz
);
