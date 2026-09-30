insert into staging.rate_cards values
('request-use1-v1','request','requests','us-east-1',0.000001,'2026-01-01T00:00:00Z',null)
on conflict (rate_card_id) do nothing;
