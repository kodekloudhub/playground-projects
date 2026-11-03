#!/usr/bin/env bash
set -euo pipefail

chmod 400 cloud-cost-pulse.pem
ssh -i cloud-cost-pulse.pem ec2-user@EC2_PUBLIC_DNS

aws sts get-caller-identity
aws configure list

export AWS_REGION=us-east-1
export ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
export RUN_ID=$(date -u +%m%d%H%M)
export FINOPS_BUCKET=cloud-cost-pulse-$ACCOUNT_ID-$RUN_ID

aws s3api create-bucket --bucket "$FINOPS_BUCKET" --region "$AWS_REGION"
aws s3api put-public-access-block --bucket "$FINOPS_BUCKET" --public-access-block-configuration BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true
aws s3api put-bucket-encryption --bucket "$FINOPS_BUCKET" --server-side-encryption-configuration '{"Rules":[{"ApplyServerSideEncryptionByDefault":{"SSEAlgorithm":"AES256"}}]}'
aws s3api put-bucket-versioning --bucket "$FINOPS_BUCKET" --versioning-configuration Status=Enabled

for prefix in raw/events raw/manifests quarantine/events silver/events silver/rates gold/snapshots ai/audit; do
  aws s3api put-object --bucket "$FINOPS_BUCKET" --key "$prefix/.keep"
done

echo "FINOPS_BUCKET=$FINOPS_BUCKET"

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
{"base_url":"REPLACE_WITH_KODEKEY_API_URL/chat/completions","api_key":"REPLACE_WITH_KODEKEY_API_KEY","model":"REPLACE_WITH_KODEKEY_MODEL"}
JSON

aws secretsmanager create-secret --name cloud-cost-pulse/kodekey --secret-string file:///tmp/kodekey-secret.json
rm -f /tmp/kodekey-secret.json

aws secretsmanager list-secrets --query "SecretList[?starts_with(Name, 'cloud-cost-pulse')].Name"

mkdir -p ~/cloud-cost-pulse/{dags,consumer,dbt/models/staging,dbt/models/intermediate,dbt/models/gold,dbt/tests,scripts,logs,plugins,config}
cd ~/cloud-cost-pulse

chmod 600 .env

docker compose build

docker compose up -d kafka kafka-ui
docker compose ps kafka kafka-ui

docker compose up -d kafka kafka-consumer
docker compose logs --tail=100 kafka-consumer

aws s3 ls "s3://$FINOPS_BUCKET/raw/manifests/"
aws s3 ls "s3://$FINOPS_BUCKET/raw/events/" --recursive

psql "host=$DB_HOST port=$DB_PORT user=$DB_USER dbname=finops sslmode=require" -f scripts/warehouse.sql

docker compose run --rm airflow-apiserver dbt --project-dir /opt/airflow/dbt debug
docker compose run --rm airflow-apiserver dbt --project-dir /opt/airflow/dbt run
docker compose run --rm airflow-apiserver dbt --project-dir /opt/airflow/dbt test

python -m py_compile consumer/consumer.py consumer/_common.py consumer/check_manifests.py consumer/validate_batch.py consumer/load_staging.py consumer/detect_anomalies.py consumer/explain_anomalies.py consumer/publish_metrics.py

python -m py_compile consumer/kodekey_provider.py consumer/explain_anomalies.py

docker compose run --rm airflow-init
docker compose up -d airflow-scheduler airflow-dag-processor airflow-apiserver kafka-consumer
docker compose ps
docker compose logs --tail=100 airflow-apiserver
docker compose logs --tail=100 kafka-consumer

aws cloudwatch list-metrics --namespace CloudCostPulse --query 'Metrics[].MetricName' --output table
