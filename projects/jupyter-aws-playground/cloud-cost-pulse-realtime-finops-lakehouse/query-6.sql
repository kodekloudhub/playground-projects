select count(*) from staging.usage_events;
select count(*) from analytics.fact_cost;
select * from analytics.fact_cost order by loaded_at desc limit 10;
select * from audit.ai_explanations order by requested_at desc;
