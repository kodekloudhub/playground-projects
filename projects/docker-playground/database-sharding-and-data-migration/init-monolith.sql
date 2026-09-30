CREATE EXTENSION IF NOT EXISTS "pgcrypto";

CREATE TABLE user_profiles (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    full_name VARCHAR(100),
    created_at TIMESTAMP DEFAULT NOW()
);

-- Generate 500 dummy records
INSERT INTO user_profiles (full_name, created_at)
SELECT 
    'Rider ' || generate_series(1, 500),
    NOW() - (random() * (interval '90 days'))
;
