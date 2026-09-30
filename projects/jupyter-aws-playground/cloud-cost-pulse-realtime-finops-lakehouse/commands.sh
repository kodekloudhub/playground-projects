#!/usr/bin/env bash
set -euo pipefail

chmod 400 cloud-cost-pulse.pem
ssh -i cloud-cost-pulse.pem ec2-user@EC2_PUBLIC_DNS

aws sts get-caller-identity
aws configure list

aws s3 ls "s3://$FINOPS_BUCKET/"

sudo dnf install -y postgresql16 || sudo dnf install -y postgresql
export DB_HOST=REPLACE_WITH_RDS_ENDPOINT
export DB_PORT=5432
export DB_USER=REPLACE_WITH_RDS_MASTER_USER
read -s DB_PASSWORD
export PGPASSWORD="$DB_PASSWORD"
psql "host=$DB_HOST port=$DB_PORT user=$DB_USER dbname=postgres sslmode=require" -c "select now();"
unset PGPASSWORD

export PGPASSWORD="$DB_PASSWORD"
psql "host=$DB_HOST port=$DB_PORT user=$DB_USER dbname=postgres sslmode=require" <<'SQL'
CREATE DATABASE airflow_meta;
CREATE DATABASE finops;
SQL
psql "host=$DB_HOST port=$DB_PORT user=$DB_USER dbname=finops sslmode=require" <<'SQL'
CREATE SCHEMA IF NOT EXISTS staging;
CREATE SCHEMA IF NOT EXISTS analytics;
CREATE SCHEMA IF NOT EXISTS audit;
SQL
unset PGPASSWORD

cat > /tmp/finops-db-secret.json <<'JSON'
{"host":"REPLACE_WITH_RDS_ENDPOINT","port":5432,"username":"REPLACE_WITH_RDS_USER","password":"REPLACE_WITH_RDS_PASSWORD","airflow_database":"airflow_meta","finops_database":"finops"}
JSON
aws secretsmanager create-secret --name cloud-cost-pulse/db --secret-string file:///tmp/finops-db-secret.json
rm -f /tmp/finops-db-secret.json

cat > /tmp/kodekey-secret.json <<'JSON'
{"base_url":"REPLACE_WITH_KODEKEY_API_URL","api_key":"REPLACE_WITH_KODEKEY_API_KEY","model":"REPLACE_WITH_KODEKEY_MODEL"}
JSON
aws secretsmanager create-secret --name cloud-cost-pulse/kodekey --secret-string file:///tmp/kodekey-secret.json
rm -f /tmp/kodekey-secret.json

aws secretsmanager list-secrets --query "SecretList[?starts_with(Name, 'cloud-cost-pulse')].Name"

mkdir -p ~/cloud-cost-pulse/{dags,consumer,dbt/models/staging,dbt/models/intermediate,dbt/models/gold,dbt/tests,scripts,logs,plugins,config}
cd ~/cloud-cost-pulse
cat > .env <<'EOF'
AWS_REGION=us-east-1
FINOPS_BUCKET=REPLACE_WITH_BUCKET
DB_SECRET_ID=cloud-cost-pulse/db
KODEKEY_SECRET_ID=cloud-cost-pulse/kodekey
KAFKA_BOOTSTRAP_SERVERS=kafka:9092
KAFKA_TOPIC=finops-usage
KAFKA_GROUP_ID=cloud-cost-pulse-consumer
BATCH_SECONDS=30
AIRFLOW_ADMIN_USERNAME=admin
AIRFLOW_ADMIN_PASSWORD=REPLACE_LOCALLY
AIRFLOW__CORE__EXECUTOR=LocalExecutor
AIRFLOW__CORE__LOAD_EXAMPLES=False
AIRFLOW__CORE__DAGS_ARE_PAUSED_AT_CREATION=False
EOF
chmod 600 .env

docker compose build

printf '%s\n' '{"event_id":"evt_01JXYZ","event_time":"2026-09-09T06:30:00Z","received_at":"2026-09-09T06:30:04Z","team":"payments","service":"checkout-api","environment":"production","region":"us-east-1","customer_id":"cust_042","usage_type":"request","quantity":1842,"unit":"requests","schema_version":"1.0"}' | \
docker compose exec -T kafka /opt/kafka/bin/kafka-console-producer.sh \
  --bootstrap-server kafka:9092 --topic finops-usage

docker compose up -d kafka kafka-consumer
docker compose logs --tail=100 kafka-consumer

aws s3 ls "s3://$FINOPS_BUCKET/raw/manifests/"
aws s3 ls "s3://$FINOPS_BUCKET/raw/events/" --recursive

psql "host=$DB_HOST port=$DB_PORT user=$DB_USER dbname=finops sslmode=require" -f scripts/warehouse.sql

docker compose run --rm airflow-apiserver dbt --project-dir /opt/airflow/dbt debug
docker compose run --rm airflow-apiserver dbt --project-dir /opt/airflow/dbt run
docker compose run --rm airflow-apiserver dbt --project-dir /opt/airflow/dbt test

docker compose run --rm airflow-init
docker compose up -d airflow-scheduler airflow-dag-processor airflow-apiserver kafka-consumer
docker compose ps
docker compose logs --tail=100 airflow-apiserver
docker compose logs --tail=100 kafka-consumer
