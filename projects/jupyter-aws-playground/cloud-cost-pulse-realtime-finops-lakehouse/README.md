# Cloud Cost Pulse — Real-Time FinOps Lakehouse

**Level:** advanced  ·  **Playground:** Jupyter | AWS Playground

▶ **[Launch the playground](https://kodekloud.com/cloud-playgrounds/aws)** — open it, then copy the files below.

A [`commands.sh`](./commands.sh) with the runnable steps is included.

```python
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
  - Airflow orchestration
  - dbt ELT and PostgreSQL analytics
  - deterministic anomaly detection
  - evidence-grounded AI explanations
prerequisites:
  - Basic Linux shell and Docker Compose usage
  - Intermediate Python and SQL knowledge
  - Familiarity with Kafka concepts and AWS networking
---

# Cloud Cost Pulse: Realtime FinOps Lakehouse

## Scenario

A SaaS platform needs a near-real-time view of cloud and platform spend. Usage events arrive continuously, but finance and platform engineering cannot reliably identify current cost drivers, budget variance, or unexpected spend.

Build a production-shaped FinOps lakehouse that ingests events from Kafka, stores immutable raw data in S3, transforms it through Airflow and dbt, calculates cost deterministically, detects anomalies, and asks KodeKey to explain the evidence.

The AI explains financial facts. It never creates or changes financial facts.

## What you'll build

You will build a FinOps lakehouse on EC2 using local Kafka, S3, PostgreSQL, Airflow, dbt, and KodeKey. The pipeline will ingest usage events, calculate costs, detect anomalies, and preserve evidence for review.

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

- Playground: **AWS Cloud Sandbox** (open it before starting)
- Playground: **KodeKey** (open it before starting)
- Basic Linux shell and Docker Compose usage
- Intermediate Python and SQL knowledge
- Familiarity with Kafka concepts and AWS networking

## Steps

This section is the executable project runbook. Replace only values marked `REPLACE_ME` in your local shell or secret store. Use the exact IAM role name shown in the steps.

### Task 1 — Prepare the environments

Open the [AWS Cloud Sandbox](https://kodekloud.com/cloud-playgrounds/aws) and [KodeKey](https://kodekloud.com/ai-playgrounds/kodekey).

Kafka runs locally on the EC2 host. Use the KodeKey API credentials and model details supplied with the lab.

Use synthetic data only. Do not paste credentials into ClickUp, Kafka messages, source files, or screenshots.

Open the AWS Console and the KodeKey API instructions in separate tabs. Record the KodeKey API base URL and model name from the API example supplied with the lab.

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
3. Allocate at least 20 GiB gp3 storage.
4. Use the default VPC and a subnet with outbound internet access.
5. Attach the IAM instance profile `iam_role_ec2`.
6. Create security group cloud-cost-pulse-ec2-sg.
7. Allow TCP 22 only from your public IP.
8. Allow TCP 8080 only from your public IP for the Airflow UI.
9. Do not expose PostgreSQL 5432 publicly.
10. Launch the instance and record its public DNS name, private IP, VPC ID, subnet ID, and security group ID.

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
2. Use a small single-AZ instance with approximately 20 GiB encrypted storage.
3. Place it in the same VPC as EC2.
4. Create cloud-cost-pulse-rds-sg.
5. Allow TCP 5432 from cloud-cost-pulse-ec2-sg only.
6. Keep public access disabled when EC2 can reach the private endpoint.
7. Record the endpoint, port, master user, and password.

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
{"base_url":"REPLACE_WITH_KODEKEY_API_URL","api_key":"REPLACE_WITH_KODEKEY_API_KEY","model":"REPLACE_WITH_KODEKEY_MODEL"}
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

Create docker-compose.yml:

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

Replace the database placeholders with URL-encoded values from the database secret. Do not commit the Compose file with real passwords.

Build the image:

```bash
docker compose build
```

### Task 9 — Create the local Kafka event source

Kafka runs locally in Docker on the EC2 host. Create the topic and use this JSON shape for producer messages:

```json
{"event_id":"evt_01JXYZ","event_time":"2026-09-09T06:30:00Z","received_at":"2026-09-09T06:30:04Z","team":"payments","service":"checkout-api","environment":"production","region":"us-east-1","customer_id":"cust_042","usage_type":"request","quantity":1842,"unit":"requests","schema_version":"1.0"}
```

Create these test cases with a local producer:

1. Normal events for payments, search, and analytics.
2. A duplicate event with the same event_id.
3. An event with no team.
4. An event with a negative quantity.
5. A delayed event with an old event_time.
6. A 5x to 10x payments/checkout-api spike.

Start the local broker and create the topic:

```bash
docker compose up -d kafka
until docker compose exec -T kafka /opt/kafka/bin/kafka-topics.sh \
  --bootstrap-server kafka:9092 --list >/dev/null 2>&1; do
  sleep 2
done
docker compose exec -T kafka /opt/kafka/bin/kafka-topics.sh \
  --bootstrap-server kafka:9092 \
  --create --if-not-exists --topic finops-usage --partitions 3 --replication-factor 1
```

Send a synthetic event directly to the local topic:

```bash
printf '%s\n' '{"event_id":"evt_01JXYZ","event_time":"2026-09-09T06:30:00Z","received_at":"2026-09-09T06:30:04Z","team":"payments","service":"checkout-api","environment":"production","region":"us-east-1","customer_id":"cust_042","usage_type":"request","quantity":1842,"unit":"requests","schema_version":"1.0"}' | \
docker compose exec -T kafka /opt/kafka/bin/kafka-console-producer.sh \
  --bootstrap-server kafka:9092 --topic finops-usage
```

Use the same command with different `event_id`, `team`, `quantity`, and
`event_time` values to create the duplicate, malformed, delayed, and spike
cases listed above.

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

def upload(records):
    now = datetime.now(timezone.utc)
    batch_id = now.strftime("%Y%m%dT%H%M%SZ") + "-" + uuid.uuid4().hex[:8]
    date_part = now.strftime("%Y-%m-%d")
    hour_part = now.strftime("%H")
    data_path = Path("/tmp") / f"{batch_id}.jsonl"
    manifest_path = Path("/tmp") / f"{batch_id}.json"
    data_path.write_text("\n".join(json.dumps(r) for r in records) + "\n")
    manifest_path.write_text(json.dumps({"batch_id": batch_id, "row_count": len(records), "created_at": now.isoformat()}))
    prefix = f"raw/events/dt={date_part}/hour={hour_part}"
    s3.upload_file(str(data_path), BUCKET, f"{prefix}/{batch_id}.jsonl")
    s3.upload_file(str(manifest_path), BUCKET, f"raw/manifests/{batch_id}.json")
    data_path.unlink(missing_ok=True)
    manifest_path.unlink(missing_ok=True)
    return batch_id

def main():
    consumer = Consumer(config())
    consumer.subscribe([TOPIC])
    records = []
    started = time.monotonic()
    try:
        while True:
            message = consumer.poll(1.0)
            if message and not message.error():
                try:
                    records.append(json.loads(message.value().decode("utf-8")))
                except json.JSONDecodeError:
                    records.append({"raw_payload": message.value().decode("utf-8", errors="replace")})
            if records and time.monotonic() - started >= BATCH_SECONDS:
                print(f"uploading rows={len(records)}", flush=True)
                print(upload(records), flush=True)
                consumer.commit(asynchronous=False)
                records = []
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
      +materialized: table
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
```

Create dbt/models/gold/fact_cost.sql:

```sql
select * from {{ ref('int_costed_usage') }}
```

Run dbt manually:

```bash
docker compose run --rm airflow-apiserver dbt --project-dir /opt/airflow/dbt debug
docker compose run --rm airflow-apiserver dbt --project-dir /opt/airflow/dbt run
docker compose run --rm airflow-apiserver dbt --project-dir /opt/airflow/dbt test
```

### Task 13 — Add validation and quarantine

Create consumer/validate_batch.py. Enforce:

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

### Task 14 — Add deterministic anomaly detection

Create consumer/detect_anomalies.py. The algorithm must:

1. Aggregate fact_cost into five-minute windows.
2. Calculate a baseline by scope and hour-of-day.
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

def explain(anomaly):
    secret = get_secret(os.environ['KODEKEY_SECRET_ID'])
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
    return response.json()
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

Open Airflow at http://EC2_PUBLIC_IP:8080. Unpause finops_microbatch and trigger one run manually.

### Task 17 — Run the end-to-end validation

1. Send normal Kafka events for three windows.
2. Confirm a manifest appears under raw/manifests/.
3. Trigger finops_microbatch.
4. Confirm validation, loading, dbt, tests, anomaly detection, and KodeKey tasks complete.
5. Query the warehouse:

```sql
select count(*) from staging.usage_events;
select count(*) from analytics.fact_cost;
select * from analytics.fact_cost order by loaded_at desc limit 10;
select * from audit.ai_explanations order by requested_at desc;
```

### Task 18 — Test the failure paths

#### Malformed event

Send an event without team or with negative quantity.

Expected:

- It is written to quarantine.
- audit.data_quality_issues contains a reason.
- Valid rows in the same batch still load.

#### Duplicate event

Send the same event_id twice.

Expected:

- One staging row.
- One fact_cost row.
- A rerun does not increase spend.

#### Late event

Send an old event_time with a current received_at.

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

1. Send normal payments events for three windows.
2. Increase checkout-api quantity by 5x to 10x for one window.
3. Wait for the consumer batch.
4. Trigger or wait for Airflow.
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

Expose these metrics through CloudWatch:

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

### Task 21 — Backfill and replay

Replay a historical S3 prefix through validation and dbt. Verify:

- Bronze objects are never modified.
- event_id prevents double counting.
- Corrected rate cards use a new model_run_id.
- Corrections create new anomaly runs instead of silently overwriting history.

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
- [ ] The operator can diagnose a failed batch from Airflow and CloudWatch.

## References & further learning

- [IAM roles for Amazon EC2](https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/iam-roles-for-amazon-ec2.html)
- [Amazon S3 security best practices](https://docs.aws.amazon.com/AmazonS3/latest/userguide/security-best-practices.html)
- [Confluent Python client for Apache Kafka](https://docs.confluent.io/kafka-clients/python/current/overview.html)
- [Running Airflow in Docker](https://airflow.apache.org/docs/apache-airflow/stable/howto/docker-compose/index.html)
- [PostgreSQL schemas](https://www.postgresql.org/docs/current/ddl-schemas.html)
- [dbt projects](https://docs.getdbt.com/docs/build/projects)
- [Publishing custom CloudWatch metrics](https://docs.aws.amazon.com/AmazonCloudWatch/latest/monitoring/publishingMetrics.html)
```
