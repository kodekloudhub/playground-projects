# Cloud Cost Pulse — Real-Time FinOps Lakehouse

**Level:** advanced  ·  **Playground:** AWS | KodeKey

▶ **[Launch the playground](https://kodekloud.com/cloud-playgrounds/aws)** — open it, then copy the files below.

A [`commands.sh`](./commands.sh) with the runnable steps is included.

```powershell
---
# ─── Metadata (read by the playground for listing & filtering) ───
id: cloud-cost-pulse-realtime-finops-lakehouse
title: Cloud Cost Pulse — Real-Time FinOps Lakehouse
playground: AWS Cloud Sandbox and KodeKey
playground_link: https://kodekloud.com/cloud-playgrounds/aws 
difficulty: advanced
estimated_minutes: 150
tags:
  - aws
  - ec2
  - kafka
  - airflow
  - dbt
  - s3
  - postgresql
  - finops
  - data-engineering
  - ai
skills:
  - AWS IAM and EC2 instance roles
  - immutable S3 Bronze storage
  - Kafka micro-batch ingestion
  - Kafka topic and message management through a browser UI
  - Airflow orchestration
  - Airflow DAG monitoring and triggering through its UI
  - dbt ELT and PostgreSQL analytics
  - deterministic anomaly detection
  - evidence-grounded AI explanations
prerequisites:
  - Basic Linux shell and Docker Compose usage
  - Intermediate Python and SQL knowledge
  - Familiarity with Kafka concepts and AWS networking
---

# Cloud Cost Pulse — Real-Time FinOps Lakehouse

## Scenario

A SaaS platform needs a near-real-time view of cloud and platform spend. Usage events arrive continuously, but finance and platform engineering cannot reliably identify current cost drivers, budget variance, or unexpected spend.

Build a production-shaped FinOps lakehouse that ingests events from Kafka, stores immutable raw data in S3, transforms it through Airflow and dbt, calculates cost deterministically, detects anomalies, and asks KodeKey to explain the evidence.

The AI explains financial facts. It never creates or changes financial facts.

## What you'll build

You will build a production-shaped FinOps lakehouse on an EC2 host. Kafka usage events will be consumed into immutable S3 Bronze objects, validated and loaded into PostgreSQL, transformed with dbt, orchestrated with Airflow, and analyzed with deterministic anomaly detection. KodeKey will explain the evidence without changing trusted financial facts.

## Learning objectives

By the end you will be able to:

- Create and attach a custom `iam_role_*` IAM role to an EC2 workload without exposing access keys.
- Design immutable, encrypted, versioned S3 Bronze storage for replayable events.
- Consume Kafka events in idempotent micro-batches and quarantine invalid records.
- Model effective-dated rates and deterministic costs in PostgreSQL and dbt.
- Orchestrate validation, ELT, anomaly detection, and explanation with Airflow.
- Separate deterministic financial facts from evidence-grounded AI explanations.
- Publish operational health metrics and troubleshoot failed pipeline runs.

## Prerequisites

- Playground: [AWS Cloud Sandbox](https://kodekloud.com/cloud-playgrounds/aws)
- Playground: [KodeKey](https://kodekloud.com/ai-playgrounds/kodekey)
- Basic Linux shell and Docker Compose usage
- Intermediate Python and SQL knowledge
- Familiarity with Kafka concepts and AWS networking

## Steps

This section is the executable project runbook. Replace only values marked `REPLACE_ME` in your local shell or secret store. Use the exact IAM role name shown in the steps.

### Task 1 — Prepare the environments

Open the AWS Console and KodeKey in separate tabs. In KodeKey, open **API Keys**, copy the Base URL and selected model from its API example, then append `/chat/completions` to the Base URL. Keep the API key in Secrets Manager or the EC2 environment; do not place it in source files or event data. Kafka runs locally on the EC2 host. Use synthetic event data. 

### Task 2 — Create the AWS IAM role

In AWS IAM, create the custom role `iam_role_ec2`:

1. Open **IAM → Roles** and select **Create role**.
2. Select **AWS service** as the trusted entity and choose **EC2** as the use case.
3. Select **Next** through the permissions step.
4. Name the role exactly `iam_role_ec2`.
5. Attach these AWS-managed policies:
   - `AmazonS3FullAccess`
   - `AWSSecretsManagerClientReadOnlyAccess`
   - `CloudWatchAgentServerPolicy`
6. Select **Create role**.
7. Open the new role and confirm its trust relationship contains `ec2.amazonaws.com`.
8. Confirm that an instance profile named `iam_role_ec2` is available for EC2.

The EC2 instance must use the `iam_role_ec2` instance profile. Do not configure personal AWS access keys on the server.

### Task 3 — Launch EC2

In EC2:

1. Choose Amazon Linux 2023.
2. Choose `t3.small`, or the smallest available instance if `t3.small` is unavailable.
3. Allocate at least 20 GiB gp3 storage. If your playground enforces gp2, use gp2 and stay within its 30 GiB limit.
4. Use the default VPC and a subnet with outbound internet access.
5. Attach the IAM instance profile `iam_role_ec2`.
6. Create security group cloud-cost-pulse-ec2-sg.
7. Create or select an EC2 key pair (for example, cloud-cost-pulse), download `cloud-cost-pulse.pem`, and keep it outside ClickUp. A fresh sandbox may have no key pair.
8. Allow TCP 22 only from your public IP. You can derive the CIDR with MY_IP=$(curl -s https://checkip.amazonaws.com)/32 and authorize it on the EC2 security group.
9. Allow TCP 8080 only from your public IP for the Airflow UI.
10. Allow TCP 8081 only from your public IP for the Kafka UI.
11. Do not expose PostgreSQL 5432 publicly.
12. Launch the instance and record its public DNS name, private IP, VPC ID, subnet ID, and security group ID.

Connect to the instance:

```bash
chmod 400 cloud-cost-pulse.pem
ssh -i cloud-cost-pulse.pem ec2-user@EC2_PUBLIC_DNS
```

Verify the role:

```bash
aws sts get-caller-identity
aws configure list
```

The caller identity should show an assumed role based on `iam_role_ec2`.

### Task 4 — Create the S3 lake

Run on EC2:

```bash
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
```

Verify:

```bash
aws s3 ls "s3://$FINOPS_BUCKET/"
```

### Task 5 — Create RDS PostgreSQL

In RDS:

1. Create a PostgreSQL instance using the smallest available instance class.
2. Use a small single-AZ instance with approximately 20 GiB encrypted storage. Before creating it, create or select a DB subnet group in the same VPC with subnets from at least two Availability Zones.

   ```bash
   VPC_ID=$(aws ec2 describe-vpcs \
     --filters Name=isDefault,Values=true \
     --query 'Vpcs[0].VpcId' --output text)
   SUBNET_IDS=$(aws ec2 describe-subnets \
     --filters "Name=vpc-id,Values=$VPC_ID" \
     --query 'Subnets[].SubnetId' --output text)
   aws rds create-db-subnet-group \
     --db-subnet-group-name cloud-cost-pulse-rds-subnets \
     --db-subnet-group-description "FinOps PostgreSQL subnets" \
     --subnet-ids $SUBNET_IDS
   ```
3. Place it in the same VPC as EC2.
4. Create cloud-cost-pulse-rds-sg.
5. Allow TCP 5432 from cloud-cost-pulse-ec2-sg only.
6. Keep public access disabled when EC2 can reach the private endpoint.
7. Record the endpoint, port, master user, and password. Wait until the DB instance status is Available before connecting. The two CREATE DATABASE statements are first-run commands; on reruns, check pg_database first and skip databases that already exist.

From EC2:

```bash
sudo dnf install -y postgresql16 || sudo dnf install -y postgresql
export DB_HOST=REPLACE_WITH_RDS_ENDPOINT
export DB_PORT=5432
export DB_USER=REPLACE_WITH_RDS_MASTER_USER
read -s DB_PASSWORD
export PGPASSWORD="$DB_PASSWORD"
psql "host=$DB_HOST port=$DB_PORT user=$DB_USER dbname=postgres sslmode=require" -c "select now();"
unset PGPASSWORD
```

Create separate logical databases:

```bash
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
```

### Task 6 — Store secrets in Secrets Manager

Create the database secret locally on EC2, use it once, then remove the file:

```bash
cat > /tmp/finops-db-secret.json <<'JSON'
{"host":"REPLACE_WITH_RDS_ENDPOINT","port":5432,"username":"REPLACE_WITH_RDS_USER","password":"REPLACE_WITH_RDS_PASSWORD","airflow_database":"airflow_meta","finops_database":"finops"}
JSON
aws secretsmanager create-secret --name cloud-cost-pulse/db --secret-string file:///tmp/finops-db-secret.json
rm -f /tmp/finops-db-secret.json
```

Create the KodeKey secret using the exact API values from KodeKey:

```bash
cat > /tmp/kodekey-secret.json <<'JSON'
{"base_url":"REPLACE_WITH_KODEKEY_API_URL/chat/completions","api_key":"REPLACE_WITH_KODEKEY_API_KEY","model":"REPLACE_WITH_KODEKEY_MODEL"}
JSON
aws secretsmanager create-secret --name cloud-cost-pulse/kodekey --secret-string file:///tmp/kodekey-secret.json
rm -f /tmp/kodekey-secret.json
```

Verify only secret names:

```bash
aws secretsmanager list-secrets --query "SecretList[?starts_with(Name, 'cloud-cost-pulse')].Name"
```

### Task 7 — Create the project directory

```bash
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
```

The `.env` file is temporary lab material. Keep it readable only by the current user and do not commit it or expose its values in logs.

### Task 8 — Build the Airflow image

Create Dockerfile:

```dockerfile
FROM apache/airflow:3.1.0-python3.12
USER root
RUN apt-get update && apt-get install -y --no-install-recommends gcc libpq-dev && apt-get clean && rm -rf /var/lib/apt/lists/*
USER airflow
RUN pip install --no-cache-dir dbt-postgres boto3 psycopg2-binary pandas pyarrow pydantic scikit-learn confluent-kafka requests
```

If that image tag is unavailable, use the stable Python 3 Airflow image tag available in the playground and keep the dependency list.

Create docker-compose.yml using the service definitions below. Keep database connection values in environment variables or local `.env`; replace `RDS_USER`, `RDS_PASSWORD`, and `RDS_ENDPOINT` with URL-encoded values from the database secret before starting Airflow. Do not commit real passwords.

```yaml
services:
  kafka:
    image: apache/kafka:3.9.0
    environment:
      KAFKA_NODE_ID: 1
      KAFKA_PROCESS_ROLES: broker,controller
      KAFKA_LISTENERS: PLAINTEXT://:9092,CONTROLLER://:9093
      KAFKA_ADVERTISED_LISTENERS: PLAINTEXT://kafka:9092
      KAFKA_CONTROLLER_LISTENER_NAMES: CONTROLLER
      KAFKA_CONTROLLER_QUORUM_VOTERS: 1@kafka:9093
      KAFKA_LISTENER_SECURITY_PROTOCOL_MAP: CONTROLLER:PLAINTEXT,PLAINTEXT:PLAINTEXT
      KAFKA_OFFSETS_TOPIC_REPLICATION_FACTOR: 1
      KAFKA_TRANSACTION_STATE_LOG_REPLICATION_FACTOR: 1
      KAFKA_TRANSACTION_STATE_LOG_MIN_ISR: 1
      KAFKA_GROUP_INITIAL_REBALANCE_DELAY_MS: 0
      KAFKA_NUM_PARTITIONS: 3
    volumes:
      - kafka-data:/var/lib/kafka/data

  kafka-ui:
    image: ghcr.io/kafbat/kafka-ui:v1.5.0
    depends_on:
      kafka:
        condition: service_started
    ports:
      - "8081:8080"
    environment:
      KAFKA_CLUSTERS_0_NAME: finops-local
      KAFKA_CLUSTERS_0_BOOTSTRAPSERVERS: kafka:9092

  airflow-init:
    build: .
    env_file: .env
    environment:
      AIRFLOW__DATABASE__SQL_ALCHEMY_CONN: postgresql+psycopg2://RDS_USER:RDS_PASSWORD@RDS_ENDPOINT:5432/airflow_meta
    volumes:
      - ./dags:/opt/airflow/dags
      - ./logs:/opt/airflow/logs
      - ./plugins:/opt/airflow/plugins
      - ./dbt:/opt/airflow/dbt
      - ./consumer:/opt/airflow/consumer
    command: >-
      bash -c "airflow db migrate && airflow users create --username $AIRFLOW_ADMIN_USERNAME --password $AIRFLOW_ADMIN_PASSWORD --firstname FinOps --lastname Operator --role Admin --email finops@example.invalid || true"

  airflow-scheduler:
    build: .
    env_file: .env
    environment:
      AIRFLOW__DATABASE__SQL_ALCHEMY_CONN: postgresql+psycopg2://RDS_USER:RDS_PASSWORD@RDS_ENDPOINT:5432/airflow_meta
    depends_on:
      airflow-init:
        condition: service_completed_successfully
    volumes:
      - ./dags:/opt/airflow/dags
      - ./logs:/opt/airflow/logs
      - ./plugins:/opt/airflow/plugins
      - ./dbt:/opt/airflow/dbt
      - ./consumer:/opt/airflow/consumer
    command: scheduler

  airflow-dag-processor:
    build: .
    env_file: .env
    environment:
      AIRFLOW__DATABASE__SQL_ALCHEMY_CONN: postgresql+psycopg2://RDS_USER:RDS_PASSWORD@RDS_ENDPOINT:5432/airflow_meta
    depends_on:
      airflow-init:
        condition: service_completed_successfully
    volumes:
      - ./dags:/opt/airflow/dags
      - ./logs:/opt/airflow/logs
      - ./plugins:/opt/airflow/plugins
      - ./dbt:/opt/airflow/dbt
      - ./consumer:/opt/airflow/consumer
    command: dag-processor

  airflow-apiserver:
    build: .
    env_file: .env
    environment:
      AIRFLOW__DATABASE__SQL_ALCHEMY_CONN: postgresql+psycopg2://RDS_USER:RDS_PASSWORD@RDS_ENDPOINT:5432/airflow_meta
    depends_on:
      airflow-init:
        condition: service_completed_successfully
    ports:
      - "8080:8080"
    volumes:
      - ./dags:/opt/airflow/dags
      - ./logs:/opt/airflow/logs
      - ./plugins:/opt/airflow/plugins
      - ./dbt:/opt/airflow/dbt
      - ./consumer:/opt/airflow/consumer
    command: api-server --port 8080

  kafka-consumer:
    build: .
    env_file: .env
    depends_on:
      kafka:
        condition: service_started
    volumes:
      - ./consumer:/opt/airflow/consumer
    command: python /opt/airflow/consumer/consumer.py

volumes:
  kafka-data:
```

Build the image:

```bash
docker compose build
```

### Task 9 — Create the local Kafka event source

Kafka runs locally in Docker on the EC2 host. You will create its topic and publish test events in the Kafbat Kafka UI. Start Kafka and its browser UI:

```bash
docker compose up -d kafka kafka-ui
docker compose ps kafka kafka-ui
```

Open `http://EC2_PUBLIC_IP:8081`. Select the `finops-local` cluster. In the UI, open **Topics**, choose **Create topic**, and enter:

- Topic name: `finops-usage`
- Partitions: `3`
- Replication factor: `1`

Open `finops-usage`, select **Messages**, then choose **Produce message** (the label may appear as **Produce**). Leave the key blank or use the event ID as the key. Paste the JSON below into the message value and send it:

```json
{"event_id":"evt_01JXYZ","event_time":"2026-09-09T06:30:00Z","received_at":"2026-09-09T06:30:04Z","team":"payments","service":"checkout-api","environment":"production","region":"us-east-1","customer_id":"cust_042","usage_type":"request","quantity":1842,"unit":"requests","schema_version":"1.0"}
```

Publish these test cases from the topic's message view. Give each new event a unique `event_id`; for the duplicate case, resend the exact same event with the same ID:

1. Normal events for payments, search, and analytics.
2. A duplicate event with the same event_id.
3. An event with no team.
4. An event with a negative quantity.
5. A delayed event with an old event_time.
6. A 5x to 10x payments/checkout-api spike.

For the missing-team test, remove `team` from the JSON. For the negative-quantity test, set `quantity` below zero. For the delayed-event test, set `event_time` well before the current date while keeping `received_at` current. For the spike, raise the payments `checkout-api` quantity to 5–10 times its normal value.

The Kafbat UI is available at `http://EC2_PUBLIC_IP:8081`; Kafka itself stays on Docker's private Compose network and does not need a public broker port.

### Task 10 — Implement the Kafka consumer

Create consumer/consumer.py:

```python
import json
import os
import time
import uuid
from datetime import datetime, timezone
from pathlib import Path

import boto3
from confluent_kafka import Consumer

REGION = os.environ["AWS_REGION"]
BUCKET = os.environ["FINOPS_BUCKET"]
TOPIC = os.environ["KAFKA_TOPIC"]
BATCH_SECONDS = int(os.environ.get("BATCH_SECONDS", "300"))
s3 = boto3.client("s3", region_name=REGION)

def config():
    result = {
        "bootstrap.servers": os.environ["KAFKA_BOOTSTRAP_SERVERS"],
        "group.id": os.environ.get("KAFKA_GROUP_ID", "cloud-cost-pulse-consumer"),
        "auto.offset.reset": "earliest",
        "enable.auto.commit": "false",
    }
    return result

def upload(records, records_read, records_failed):
    now = datetime.now(timezone.utc)
    batch_id = now.strftime("%Y%m%dT%H%M%SZ") + "-" + uuid.uuid4().hex[:8]
    date_part = now.strftime("%Y-%m-%d")
    hour_part = now.strftime("%H")
    data_path = Path("/tmp") / f"{batch_id}.jsonl"
    manifest_path = Path("/tmp") / f"{batch_id}.json"
    data_path.write_text("\n".join(json.dumps(r) for r in records) + ("\n" if records else ""))
    prefix = f"raw/events/dt={date_part}/hour={hour_part}"
    upload_started = time.monotonic()
    s3.upload_file(str(data_path), BUCKET, f"{prefix}/{batch_id}.jsonl")
    batch_upload_seconds = round(time.monotonic() - upload_started, 3)
    manifest = {
        "batch_id": batch_id,
        "row_count": len(records),
        "records_read": records_read,
        "records_failed": records_failed,
        "batch_upload_seconds": batch_upload_seconds,
        "created_at": now.isoformat(),
    }
    manifest_path.write_text(json.dumps(manifest))
    s3.upload_file(str(manifest_path), BUCKET, f"raw/manifests/{batch_id}.json")
    data_path.unlink(missing_ok=True)
    manifest_path.unlink(missing_ok=True)
    return batch_id, batch_upload_seconds

def main():
    consumer = Consumer(config())
    consumer.subscribe([TOPIC])
    records = []
    records_read = 0
    records_failed = 0
    started = time.monotonic()
    try:
        while True:
            message = consumer.poll(1.0)
            if message is not None and message.error():
                records_failed += 1
            elif message is not None:
                records_read += 1
                try:
                    records.append(json.loads(message.value().decode("utf-8")))
                except (UnicodeDecodeError, json.JSONDecodeError):
                    records_failed += 1
                    records.append({"raw_payload": message.value().decode("utf-8", errors="replace")})
            if (records or records_failed) and time.monotonic() - started >= BATCH_SECONDS:
                batch_id, batch_upload_seconds = upload(records, records_read, records_failed)
                print(json.dumps({"batch_id": batch_id, "records_read": records_read,
                                  "records_failed": records_failed,
                                  "batch_upload_seconds": batch_upload_seconds}), flush=True)
                consumer.commit(asynchronous=False)
                records = []
                records_read = 0
                records_failed = 0
                started = time.monotonic()
    finally:
        consumer.close()

if __name__ == "__main__":
    main()
```

Start the local consumer:

```bash
docker compose up -d kafka kafka-consumer
docker compose logs --tail=100 kafka-consumer
```

From another SSH session, verify uploads:

```bash
aws s3 ls "s3://$FINOPS_BUCKET/raw/manifests/"
aws s3 ls "s3://$FINOPS_BUCKET/raw/events/" --recursive
```

The consumer must preserve each source `event_id` and `batch_id`. Downstream loading must use `INSERT ... ON CONFLICT (event_id) DO NOTHING`; repeated records are counted once and any duplicate is written to `audit.data_quality_issues`.

Each S3 manifest also stores `records_read`, `records_failed`, and `batch_upload_seconds`. `records_read` counts Kafka messages successfully returned to the consumer. `records_failed` counts Kafka message errors and JSON decoding failures; schema or business-rule rejections are counted separately as quarantined pipeline rows.

### Task 11 — Create warehouse tables

Create scripts/warehouse.sql:

```sql
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
  event_id text not null,
  rate_card_id text not null,
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
  loaded_at timestamptz not null default now(),
  primary key (event_id, model_run_id)
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
```

Run it:

```bash
psql "host=$DB_HOST port=$DB_PORT user=$DB_USER dbname=finops sslmode=require" -f scripts/warehouse.sql
```

Insert a rate card and budget using psql:

```sql
insert into staging.rate_cards values
('request-use1-v1','request','requests','us-east-1',0.000001,'2026-01-01T00:00:00Z',null)
on conflict (rate_card_id) do nothing;
```

### Task 12 — Configure dbt

Create dbt/profiles.yml:

```yaml
cloud_cost_pulse:
  target: prod
  outputs:
    prod:
      type: postgres
      host: RDS_ENDPOINT
      user: RDS_USER
      password: RDS_PASSWORD
      port: 5432
      dbname: finops
      schema: analytics
      threads: 2
      sslmode: require
```

Create `dbt/macros/generate_schema_name.sql` so the schemas in `dbt_project.yml` are used exactly (without the target-schema prefix):

```sql
{% macro generate_schema_name(custom_schema_name, node) -%}
  {{ custom_schema_name | trim if custom_schema_name else target.schema }}
{%- endmacro %}
```

Create dbt/dbt_project.yml:

```yaml
name: cloud_cost_pulse
version: 1.0.0
config-version: 2
profile: cloud_cost_pulse
model-paths: [models]
test-paths: [tests]
models:
  cloud_cost_pulse:
    staging:
      +schema: staging
      +materialized: view
    intermediate:
      +schema: analytics
      +materialized: table
    gold:
      +schema: analytics
      +materialized: incremental
```

Create dbt/models/staging/stg_usage_events.sql:

```sql
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
```

Create dbt/models/intermediate/int_costed_usage.sql:

```sql
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
  r.rate_card_id,
  r.price_per_unit,
  u.quantity * r.price_per_unit as estimated_cost,
  u.batch_id,
  md5(u.event_id || ':' || r.rate_card_id) as model_run_id
from {{ ref('stg_usage_events') }} u
join staging.rate_cards r
  on r.usage_type = u.usage_type
 and r.unit = u.unit
 and r.region = u.region
 and u.event_time >= r.effective_from
 and (r.effective_to is null or u.event_time < r.effective_to)
```

Create dbt/models/gold/fact_cost.sql:

```sql
{{ config(materialized='incremental', unique_key=['event_id', 'model_run_id']) }}

select * from {{ ref('int_costed_usage') }}
```

The composite key makes reruns idempotent for the same event and rate-card version. When a corrected rate uses a new `rate_card_id`, dbt appends that new model run while retaining the earlier fact row.
Do not use `dbt run --full-refresh` after the fact table has version history; a full refresh rebuilds the incremental table and removes retained prior versions.

Run dbt manually:

```bash
docker compose run --rm airflow-apiserver dbt --project-dir /opt/airflow/dbt debug
docker compose run --rm airflow-apiserver dbt --project-dir /opt/airflow/dbt run
docker compose run --rm airflow-apiserver dbt --project-dir /opt/airflow/dbt test
```

### Task 13 — Add validation and quarantine

The DAG calls these helper files, so create them before the first run: `check_manifests.py`, `validate_batch.py`, `load_staging.py`, `detect_anomalies.py`, `explain_anomalies.py`, and `publish_metrics.py`. If any is missing, the DAG fails with “file not found”.

The validator enforces:

1. event_id is present.
2. event_time and received_at are valid UTC timestamps.
3. team, service, environment, region, usage_type, and unit are present.
4. quantity is numeric and non-negative.
5. usage_type and unit are an accepted pair.
6. schema_version is supported.
7. duplicate event_id values are recorded but counted once.

For each rejected event:

- Upload the original record to quarantine/events/batch_id=.../.
- Insert an audit.data_quality_issues row.
- Continue the batch for record-level errors.
- Fail the task only for batch-level errors such as unreadable S3 or unavailable PostgreSQL.

Create the six helper files and the small shared module below. Each script is independently executable by Airflow and carries the selected `batch_id` through `/tmp/cloud-cost-pulse-batch.json`.

```bash
cat > consumer/_common.py <<'PY'
import json
import os
from pathlib import Path
import boto3
import psycopg2

STATE = Path(os.environ.get("BATCH_STATE_FILE", "/tmp/cloud-cost-pulse-batch.json"))

def load_state():
    if not STATE.exists():
        raise RuntimeError(f"missing batch state: {STATE}")
    return json.loads(STATE.read_text())

def save_state(state):
    STATE.write_text(json.dumps(state))

def db_secret():
    sm = boto3.client("secretsmanager", region_name=os.environ["AWS_REGION"])
    return json.loads(sm.get_secret_value(SecretId=os.environ["DB_SECRET_ID"])["SecretString"])

def db_conn():
    s = db_secret()
    return psycopg2.connect(
        host=s["host"], port=s.get("port", 5432), user=s["username"],
        password=s["password"], dbname=s.get("finops_database", "finops"),
        sslmode="require",
    )

def log_done(task, batch_id, started, input_rows, output_rows, prefix, tables):
    import time
    print(json.dumps({"dag_id": os.environ.get("AIRFLOW_CTX_DAG_ID", "finops_microbatch"),
      "task_id": os.environ.get("AIRFLOW_CTX_TASK_ID", task),
      "run_id": os.environ.get("AIRFLOW_CTX_RUN_ID", "manual"), "batch_id": batch_id,
      "input_row_count": input_rows, "output_row_count": output_rows,
      "affected_s3_prefix": prefix, "database_tables": tables,
      "elapsed_seconds": round(time.monotonic() - started, 3)}), flush=True)
PY

cat > consumer/check_manifests.py <<'PY'
import json, os, time
from pathlib import Path
import boto3
from _common import save_state

started = time.monotonic(); region = os.environ["AWS_REGION"]; bucket = os.environ["FINOPS_BUCKET"]
s3 = boto3.client("s3", region_name=region)
manifest_keys = []
for page in s3.get_paginator("list_objects_v2").paginate(Bucket=bucket, Prefix="raw/manifests/"):
    manifest_keys.extend(o["Key"] for o in page.get("Contents", []))
if not manifest_keys:
    raise RuntimeError("no raw manifest found")
key = sorted(manifest_keys)[-1]
manifest = json.loads(s3.get_object(Bucket=bucket, Key=key)["Body"].read())
batch_id = manifest["batch_id"]
event_key = None
for page in s3.get_paginator("list_objects_v2").paginate(Bucket=bucket, Prefix="raw/events/"):
    for obj in page.get("Contents", []):
        if obj["Key"].endswith(f"/{batch_id}.jsonl"):
            event_key = obj["Key"]; break
    if event_key: break
if not event_key:
    raise RuntimeError(f"event object not found for batch {batch_id}")
save_state({"batch_id": batch_id, "manifest_key": key, "event_key": event_key,
            "row_count": manifest["row_count"], "records_read": manifest["records_read"],
            "records_failed": manifest["records_failed"],
            "batch_upload_seconds": manifest["batch_upload_seconds"]})
print(json.dumps({"dag_id": os.environ.get("AIRFLOW_CTX_DAG_ID", "finops_microbatch"),
  "task_id": os.environ.get("AIRFLOW_CTX_TASK_ID", "check_new_manifests"),
  "run_id": os.environ.get("AIRFLOW_CTX_RUN_ID", "manual"), "batch_id":batch_id,
  "input_row_count":manifest.get("row_count",0), "output_row_count":1,
  "affected_s3_prefix":"raw/manifests/", "database_tables":[],
  "elapsed_seconds":round(time.monotonic()-started,3)}), flush=True)
PY

cat > consumer/validate_batch.py <<'PY'
import json, os, time, uuid
from datetime import datetime, timezone
from decimal import Decimal, InvalidOperation
import boto3
from _common import db_conn, load_state, log_done, save_state

started=time.monotonic(); state=load_state(); batch=state["batch_id"]; region=os.environ["AWS_REGION"]; bucket=os.environ["FINOPS_BUCKET"]
s3=boto3.client("s3", region_name=region); raw=s3.get_object(Bucket=bucket,Key=state["event_key"])["Body"].read().decode()
required=("event_id","event_time","received_at","team","service","environment","region","customer_id","usage_type","unit","quantity","schema_version")
pairs={"request":"requests","storage":"GB-hours","egress":"GB"}; supported={"1.0"}
valid=[]; issues=[]; seen=set()
def reject(record,eid,kind,detail):
    qkey=f"quarantine/events/batch_id={batch}/{eid or uuid.uuid4().hex}.json"
    s3.put_object(Bucket=bucket,Key=qkey,Body=(json.dumps(record)+"\n").encode(),ContentType="application/json")
    issues.append((eid,kind,detail))
for line_no,line in enumerate(raw.splitlines(),1):
    try: record=json.loads(line)
    except json.JSONDecodeError as e:
        reject({"raw_payload":line},None,"invalid_json",f"line {line_no}: {e.msg}"); continue
    if not isinstance(record, dict):
        reject({"raw_payload":line},None,"invalid_record","JSON event must be an object"); continue
    eid=str(record.get("event_id","")).strip()
    if eid in seen:
        reject(record,eid,"duplicate_event_id","duplicate within batch"); continue
    seen.add(eid)
    try:
        missing=[k for k in required if record.get(k) in (None,"")]
        if missing: raise ValueError("missing: "+", ".join(missing))
        for k in ("event_time","received_at"):
            dt=datetime.fromisoformat(str(record[k]).replace("Z","+00:00"))
            if dt.tzinfo is None: raise ValueError(f"{k} must include UTC timezone")
            record[k]=dt.astimezone(timezone.utc).isoformat()
        quantity=Decimal(str(record["quantity"]))
        if quantity < 0: raise ValueError("quantity must be non-negative")
        if pairs.get(record["usage_type"]) != record["unit"]: raise ValueError("usage_type/unit pair is unsupported")
        if record["schema_version"] not in supported: raise ValueError("unsupported schema_version")
        record["batch_id"]=batch; valid.append(record)
    except (ValueError,InvalidOperation,TypeError) as e:
        reject(record,eid,"validation_error",str(e))
conn=db_conn()
with conn:
    with conn.cursor() as cur:
        cur.executemany("""insert into audit.data_quality_issues(batch_id,event_id,issue_type,issue_detail) values (%s,%s,%s,%s)""",[(batch,eid,k,d) for eid,k,d in issues])
conn.close()
valid_path=f"/tmp/cloud-cost-pulse-valid-{batch}.jsonl"; Path(valid_path).write_text("\n".join(json.dumps(r) for r in valid)+("\n" if valid else ""))
state.update({"valid_path":valid_path,"valid_count":len(valid),"issue_count":len(issues)}) ; save_state(state)
log_done("validate_batch",batch,started,state.get("row_count",0),len(valid),f"quarantine/events/batch_id={batch}/",["audit.data_quality_issues"])
PY

cat > consumer/load_staging.py <<'PY'
import json, time
from _common import db_conn, load_state, log_done, save_state
started=time.monotonic(); state=load_state(); batch=state["batch_id"]
rows=[json.loads(x) for x in open(state["valid_path"]) if x.strip()]; loaded=duplicates=0
conn=db_conn()
with conn:
    with conn.cursor() as cur:
        for r in rows:
            cur.execute("""insert into staging.usage_events(event_id,event_time,received_at,team,service,environment,region,customer_id,usage_type,quantity,unit,schema_version,batch_id) values (%(event_id)s,%(event_time)s,%(received_at)s,%(team)s,%(service)s,%(environment)s,%(region)s,%(customer_id)s,%(usage_type)s,%(quantity)s,%(unit)s,%(schema_version)s,%(batch_id)s) on conflict (event_id) do nothing""",r)
            if cur.rowcount: loaded+=1
            else:
                duplicates+=1
                cur.execute("insert into audit.data_quality_issues(batch_id,event_id,issue_type,issue_detail) values (%s,%s,%s,%s)",(batch,r["event_id"],"duplicate_event_id","already present in staging"))
conn.close(); state.update({"loaded_count":loaded,"duplicate_count":duplicates}); save_state(state)
log_done("load_staging",batch,started,len(rows),loaded,"raw/events/",["staging.usage_events","audit.data_quality_issues"])
PY

cat > consumer/detect_anomalies.py <<'PY'
import hashlib, os, time
from datetime import timedelta
from decimal import Decimal
from _common import db_conn, log_done
started=time.monotonic(); conn=db_conn(); conn.autocommit=False
with conn:
    with conn.cursor() as cur:
        cur.execute("""with current_cost as (select distinct on (event_id) event_id,event_time,team,service,environment,region,estimated_cost from analytics.fact_cost order by event_id,loaded_at desc,model_run_id desc) select concat_ws(':',coalesce(team,''),coalesce(service,''),environment,region) scope_id, date_trunc('hour',event_time)+floor(extract(minute from event_time)/5)*interval '5 minutes' window_start, sum(estimated_cost) cost from current_cost group by 1,2 order by 2""")
        rows=cur.fetchall()
        if rows:
            current=max(r[1] for r in rows); current_rows=[r for r in rows if r[1]==current]
            for scope,window,observed in current_rows:
                history=[r[2] for r in rows if r[0]==scope and current-timedelta(days=7)<=r[1]<current and r[1].hour==window.hour and (r[1].minute//5)==(window.minute//5)]
                if len(history)<3:
                    print(f"no anomaly scope={scope} window={window.isoformat()} reason=insufficient comparable history count={len(history)}",flush=True); continue
                baseline=sum(history,Decimal("0"))/Decimal(len(history)); absolute=Decimal(observed)-baseline; pct=(absolute/baseline*100) if baseline else Decimal("999999")
                if pct < 50 or absolute < 5: continue
                severity="critical" if pct>=200 else "warning"; evidence=f"{window.isoformat()}/{(window+timedelta(minutes=5)).isoformat()}"; anomaly=hashlib.sha256(f"{scope}|{evidence}".encode()).hexdigest()[:32]
                cur.execute("""insert into analytics.fact_anomaly(anomaly_id,detected_at,scope_id,baseline_cost,observed_cost,absolute_delta,percentage_delta,detection_method,severity,evidence_window,detector_version) values (%s,now(),%s,%s,%s,%s,%s,'five_minute_baseline',%s,%s,'v1') on conflict (anomaly_id) do nothing""",(anomaly,scope,baseline,observed,absolute,pct,severity,evidence))
conn.close(); log_done("detect_anomalies","latest",started,len(rows),0,"analytics.fact_cost",["analytics.fact_cost","analytics.fact_anomaly"])
PY

cat > consumer/explain_anomalies.py <<'PY'
import json, os, time
from datetime import datetime, timezone
from _common import db_conn, log_done
from kodekey_provider import explain, get_secret
started=time.monotonic(); secret=get_secret(os.environ["KODEKEY_SECRET_ID"])
conn=db_conn(); processed=0
with conn:
    with conn.cursor() as cur:
        cur.execute("""select a.anomaly_id,a.scope_id,a.baseline_cost,a.observed_cost,a.percentage_delta,a.evidence_window,a.detector_version from analytics.fact_anomaly a where a.status='open' and not exists (select 1 from audit.ai_explanations x where x.anomaly_id=a.anomaly_id and x.status='succeeded')""")
        for row in cur.fetchall():
            anomaly={"anomaly_id":row[0],"scope_id":row[1],"baseline_cost":str(row[2]),"observed_cost":str(row[3]),"percentage_delta":str(row[4]),"evidence_window":row[5],"detector_version":row[6]}
            status="succeeded"; response_payload=None; payload=None
            try:
                payload,response_payload=explain(anomaly,secret)
            except Exception as e:
                status="failed"; response_payload={"error":str(e)}
            cur.execute("""insert into audit.ai_explanations(anomaly_id,model_name,prompt_version,request_payload,response_payload,status,requested_at,completed_at) values (%s,%s,%s,%s::jsonb,%s::jsonb,%s,%s,%s)""",(row[0],secret["model"],"v1",json.dumps(payload),json.dumps(response_payload) if response_payload is not None else None,status,datetime.now(timezone.utc),datetime.now(timezone.utc))); processed+=1
conn.close(); log_done("explain_anomalies", "latest", started, processed, processed, "", ["analytics.fact_anomaly","audit.ai_explanations"])
PY

cat > consumer/publish_metrics.py <<'PY'
import os, time
import boto3
from _common import db_conn, load_state, log_done
started=time.monotonic(); state=load_state(); batch=state["batch_id"]; region=os.environ["AWS_REGION"]; env=os.environ.get("ENVIRONMENT","production")
records_read=int(state["records_read"])
records_failed=int(state["records_failed"])
batch_upload_seconds=float(state["batch_upload_seconds"])
conn=db_conn()
with conn.cursor() as cur:
    cur.execute("select count(*) from staging.usage_events where batch_id=%s",(batch,)); loaded=cur.fetchone()[0]
    cur.execute("select count(*) from audit.data_quality_issues where batch_id=%s",(batch,)); quarantined=cur.fetchone()[0]
    cur.execute("select count(*) from analytics.fact_anomaly where status='open'"); open_count=cur.fetchone()[0]
    cur.execute("select count(*) from audit.ai_explanations where requested_at >= now()-interval '15 minutes'"); requests_count=cur.fetchone()[0]
    cur.execute("select count(*) from audit.ai_explanations where status='failed' and requested_at >= now()-interval '15 minutes'"); failures=cur.fetchone()[0]
    cur.execute("select extract(epoch from (now()-max(loaded_at))) from staging.usage_events"); freshness=cur.fetchone()[0] or 0
conn.close()
dims=[{"Name":"Environment","Value":env},{"Name":"Region","Value":region}]
data=[]
metrics=[
    ("consumer.records_read",records_read,"Count"),
    ("consumer.records_failed",records_failed,"Count"),
    ("consumer.batch_upload_seconds",batch_upload_seconds,"Seconds"),
    ("pipeline.rows_loaded",loaded,"Count"),
    ("pipeline.rows_quarantined",quarantined,"Count"),
    ("pipeline.freshness_seconds",float(freshness),"Seconds"),
    ("anomaly.open_count",open_count,"Count"),
    ("kodekey.request_count",requests_count,"Count"),
    ("kodekey.failure_count",failures,"Count"),
]
for name,value,unit in metrics:
    data.append({"MetricName":name,"Dimensions":dims,"Value":value,"Unit":unit})
boto3.client("cloudwatch",region_name=region).put_metric_data(Namespace="CloudCostPulse",MetricData=data)
log_done("publish_metrics",batch,started,loaded,len(data),"",["staging.usage_events","audit.data_quality_issues","analytics.fact_anomaly","audit.ai_explanations"])
PY

python -m py_compile consumer/consumer.py consumer/_common.py consumer/check_manifests.py consumer/validate_batch.py consumer/load_staging.py consumer/detect_anomalies.py consumer/explain_anomalies.py consumer/publish_metrics.py
```

Run the compile check before starting Airflow. The scripts intentionally fail on unreadable S3, missing state, unavailable PostgreSQL, or failed CloudWatch writes; individual malformed records are quarantined and do not stop the batch.

### Task 14 — Review deterministic anomaly detection

Review the supplied `consumer/detect_anomalies.py`. It must:

1. Aggregate fact_cost into five-minute windows.
2. Calculate a baseline by scope and hour-of-day from the previous seven days, requiring at least three comparable windows; with insufficient history, record no anomaly and explain the reason.
3. Compute absolute_delta and percentage_delta.
4. Require both a percentage threshold and an absolute minimum.
5. Generate a stable anomaly_id from scope and evidence window.
6. Use insert-on-conflict behavior so reruns do not duplicate incidents.

Initial thresholds:

- percentage_delta >= 50 percent
- absolute_delta >= 5 currency units
- severity critical when percentage_delta >= 200 percent

The detector, not the AI, decides whether the anomaly exists.

### Task 15 — Add the KodeKey adapter

Create consumer/kodekey_provider.py. Use the exact endpoint and payload format shown in the KodeKey API example:

```python
import json
import os
import boto3
import requests

def get_secret(secret_id):
    client = boto3.client('secretsmanager', region_name=os.environ['AWS_REGION'])
    result = client.get_secret_value(SecretId=secret_id)
    return json.loads(result['SecretString'])

def explain(anomaly, secret=None):
    secret = secret or get_secret(os.environ['KODEKEY_SECRET_ID'])
    request_body = {
        'model': secret['model'],
        'messages': [{
            'role': 'user',
            'content': json.dumps({
                'instruction': 'Explain this FinOps anomaly using only the supplied evidence. Return structured JSON.',
                'anomaly': anomaly,
            })
        }],
        'temperature': 0.1,
    }
    response = requests.post(
        secret['base_url'],
        headers={'Authorization': f"Bearer {secret['api_key']}", 'Content-Type': 'application/json'},
        json=request_body,
        timeout=30,
    )
    response.raise_for_status()
    return request_body, response.json()
```

Send only:

- anomaly_id
- team and service
- environment and region
- baseline and observed cost
- percentage delta
- top usage dimensions
- rate-card version
- detector version

Do not send secrets, raw customer records, or entire Kafka batches. Store model_name, prompt_version, request payload, response payload, status, and timestamps in audit.ai_explanations.

Compile the adapter and its caller:

```bash
python -m py_compile consumer/kodekey_provider.py consumer/explain_anomalies.py
```

### Task 16 — Create the Airflow DAG

Create dags/finops_microbatch.py:

```python
from datetime import datetime, timedelta
from airflow import DAG
from airflow.operators.bash import BashOperator

with DAG(
    dag_id='finops_microbatch',
    start_date=datetime(2026, 1, 1),
    schedule='*/5 * * * *',
    catchup=False,
    default_args={'owner': 'finops', 'retries': 2, 'retry_delay': timedelta(minutes=1)},
    tags=['finops', 'elt', 'kodekey'],
) as dag:
    check = BashOperator(task_id='check_new_manifests', bash_command='python /opt/airflow/consumer/check_manifests.py')
    validate = BashOperator(task_id='validate_batch_schema', bash_command='python /opt/airflow/consumer/validate_batch.py')
    load = BashOperator(task_id='load_staging_tables', bash_command='python /opt/airflow/consumer/load_staging.py')
    dbt_run = BashOperator(task_id='run_dbt_models', bash_command='dbt --project-dir /opt/airflow/dbt run')
    dbt_test = BashOperator(task_id='run_dbt_tests', bash_command='dbt --project-dir /opt/airflow/dbt test')
    detect = BashOperator(task_id='detect_anomalies', bash_command='python /opt/airflow/consumer/detect_anomalies.py')
    explain = BashOperator(task_id='explain_anomalies_with_kodekey', bash_command='python /opt/airflow/consumer/explain_anomalies.py')
    publish = BashOperator(task_id='publish_snapshot_and_metrics', bash_command='python /opt/airflow/consumer/publish_metrics.py')
    check >> validate >> load >> dbt_run >> dbt_test >> detect >> explain >> publish
```

Every helper must log dag_id, task_id, run_id, batch_id, input row count, output row count, affected S3 prefix, database tables, and elapsed time.

Initialize and start:

```bash
docker compose run --rm airflow-init
docker compose up -d airflow-scheduler airflow-dag-processor airflow-apiserver kafka-consumer
docker compose ps
docker compose logs --tail=100 airflow-apiserver
docker compose logs --tail=100 kafka-consumer
```

The DAG is authored in `dags/finops_microbatch.py`; Airflow discovers that file and exposes the DAG in its UI. Airflow's UI is for operating and inspecting the DAG, not editing its Python definition.

Open `http://EC2_PUBLIC_IP:8080` and sign in with `AIRFLOW_ADMIN_USERNAME` and `AIRFLOW_ADMIN_PASSWORD` from `.env`. Then:

1. Open **DAGs** and locate `finops_microbatch`.
2. Wait for the DAG to appear. If it is paused, switch it on.
3. Select the DAG and choose **Trigger** to run it now.
4. Open **Grid** or **Graph** to watch the tasks.
5. Select a task instance and open **Logs** to inspect its result.

The DAG also runs on its five-minute schedule after it is unpaused.

### Task 17 — Run the end-to-end validation

1. Use the Kafka UI at `http://EC2_PUBLIC_IP:8081` to send normal events for three windows.
2. Confirm a manifest appears under `raw/manifests/`.
3. In the Airflow UI at `http://EC2_PUBLIC_IP:8080`, trigger `finops_microbatch`.
4. In Grid or Graph view, confirm validation, loading, dbt, tests, anomaly detection, and KodeKey tasks complete; open task logs for details.
5. Query the warehouse:

```sql
select count(*) from staging.usage_events;
select count(*) from analytics.fact_cost;
select * from analytics.fact_cost order by loaded_at desc limit 10;
select * from audit.ai_explanations order by requested_at desc;
```

Confirm CloudWatch receives all nine `CloudCostPulse` metrics listed in Task 20, including the three `consumer.*` metrics.

```bash
aws cloudwatch list-metrics --namespace CloudCostPulse --query 'Metrics[].MetricName' --output table
```

### Task 18 — Test the failure paths

#### Malformed event

In the Kafka UI, open `finops-usage` → **Messages** → **Produce message**. Send an event without `team`, then send another with a negative `quantity`.

Expected:

- It is written to quarantine.
- audit.data_quality_issues contains a reason.
- Valid rows in the same batch still load.

#### Duplicate event

In the Kafka UI, send the same event value twice with the same `event_id`.

Expected:

- One staging row.
- One fact_cost row.
- A rerun does not increase spend.

#### Late event

In the Kafka UI, send an event with an old `event_time` and a current `received_at`.

Expected:

- event_time controls the cost window.
- received_at remains available for ingestion-latency analysis.
- The historical partition can be replayed.

#### Airflow retry

Temporarily make the database connection fail, trigger the DAG, restore the connection, and retry the task.

Expected:

- A clear failure log.
- Automatic retry.
- No duplicate cost after recovery.

### Task 19 — Inject the FinOps anomaly

1. In the Kafka UI, send normal payments events for three windows.
2. Increase checkout-api quantity by 5x to 10x for one window.
3. Wait for the consumer batch.
4. In the Airflow UI, wait for the scheduled run or trigger `finops_microbatch` manually.
5. Confirm exactly one open anomaly.
6. Confirm an AI explanation exists.

```sql
select anomaly_id, scope_id, baseline_cost, observed_cost, percentage_delta, severity
from analytics.fact_anomaly
order by detected_at desc;

select anomaly_id, model_name, prompt_version, status, requested_at, completed_at
from audit.ai_explanations
order by requested_at desc;
```

The expected AI result is a concise explanation with evidence, likely drivers, recommended checks, confidence, and uncertainty. The AI must not modify financial facts or AWS resources.

### Task 20 — Add operational checks

Expose these metrics through CloudWatch namespace `CloudCostPulse`; include `Environment` and `Region` dimensions on every metric:

- consumer.records_read
- consumer.records_failed
- consumer.batch_upload_seconds
- pipeline.rows_loaded
- pipeline.rows_quarantined
- pipeline.freshness_seconds
- anomaly.open_count
- kodekey.request_count
- kodekey.failure_count

Create alarms for no batch for 15 minutes, quarantine rate above 5 percent, Airflow DAG failure, KodeKey failure rate above 20 percent, and database connection failure.

The gold `analytics.fact_cost` model is incremental and unique on `(event_id, model_run_id)`. Include `rate_card_id` in the fact and derive `model_run_id` from `event_id` plus `rate_card_id`. When replacing a rate, close the old card with `effective_to` before inserting a new effective-dated card with a new `rate_card_id`.

### Task 21 — Backfill and replay

Close the previous rate card with `effective_to` and insert its corrected replacement with a new `rate_card_id`, as described in Task 20. Replay a historical S3 prefix through validation and dbt. Verify:

- Bronze objects are never modified.
- event_id prevents double counting.
- Corrected rate cards use a new model_run_id.
- Corrections create new anomaly runs instead of silently overwriting history.

For an event recalculated with a corrected rate card, verify that both versions remain in the fact table:

```sql
select event_id, rate_card_id, model_run_id, estimated_cost
from analytics.fact_cost
where event_id = 'REPLACE_WITH_REPLAYED_EVENT_ID'
order by loaded_at, rate_card_id;
```

The same `event_id` should have a row for each applied rate-card version, with a distinct `model_run_id`.

## Validation

- [ ] Kafka events travel to S3 and PostgreSQL.
- [ ] Duplicate events do not double-count spend.
- [ ] Invalid records are quarantined with reasons.
- [ ] Cost uses effective-dated rates.
- [ ] A controlled spike creates one anomaly.
- [ ] Airflow retries safely.
- [ ] Historical data can be replayed.
- [ ] KodeKey produces a structured evidence-grounded explanation.
- [ ] AI output is stored separately from trusted financial facts.
- [ ] CloudWatch exposes pipeline and AI health.

## References & further learning

- [IAM roles for Amazon EC2](https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/iam-roles-for-amazon-ec2.html)
- [Amazon S3 security best practices](https://docs.aws.amazon.com/AmazonS3/latest/userguide/security-best-practices.html)
- [Confluent Python client for Apache Kafka](https://docs.confluent.io/kafka-clients/python/current/overview.html)
- [Kafbat Kafka UI](https://github.com/kafbat/kafka-ui)
- [Running Airflow in Docker](https://airflow.apache.org/docs/apache-airflow/stable/howto/docker-compose/index.html)
- [Airflow UI](https://airflow.apache.org/docs/apache-airflow/stable/ui.html)
- [PostgreSQL schemas](https://www.postgresql.org/docs/current/ddl-schemas.html)
- [dbt projects](https://docs.getdbt.com/docs/build/projects)
- [dbt incremental models](https://docs.getdbt.com/docs/build/incremental-models)
- [Publishing custom CloudWatch metrics](https://docs.aws.amazon.com/AmazonCloudWatch/latest/monitoring/publishingMetrics.html)
- [KodeKey](https://kodekloud.com/ai-playgrounds/kodekey)
```
