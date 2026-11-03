{{ config(materialized='incremental', unique_key=['event_id', 'model_run_id']) }}

select * from {{ ref('int_costed_usage') }}
