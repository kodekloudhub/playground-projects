# AI Cloud Cost Monitor

## Project info

- **ID:** cloud-cost-pulse-realtime-finops-lakehouse
- **Title:** Cloud Cost Pulse - Real-Time FinOps Lakehouse
- **Playground:** AWS Cloud Sandbox and KodeKey
- **Playground link:** [https://kodekloud.com/cloud-playgrounds/aws](https://kodekloud.com/cloud-playgrounds/aws)
- **Difficulty:** advanced
- **Estimated minutes:** 150
- **Tags:**
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
- **Skills:**
  - AWS IAM and EC2 instance roles
  - immutable S3 Bronze storage
  - Kafka micro-batch ingestion
  - Kafka topic and message management through a browser UI
  - Airflow orchestration
  - Airflow DAG monitoring and triggering through its UI
  - dbt ELT and PostgreSQL analytics
  - deterministic anomaly detection
  - evidence-grounded AI explanations
- **Prerequisites:**
  - Basic Linux shell and Docker Compose usage
  - Intermediate Python and SQL knowledge
  - Familiarity with Kafka concepts and AWS networking

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

### Task 1 - Prepare the environments

Open the AWS Console and KodeKey in separate tabs. In KodeKey, open **API Keys**, copy the Base URL and selected model from its API example, then append `/chat/completions` to the Base URL. Keep the API key in Secrets Manager or the EC2 environment; do not place it in source files or event data. Kafka runs locally on the EC2 host. Use synthetic event data. 

### Task 2 - Create the AWS IAM role

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

### Task 3 - Launch EC2

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

### Task 4 - Create the S3 lake

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

### Task 5 - Create RDS PostgreSQL

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

### Task 6 - Store secrets in Secrets Manager

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

### Task 7 - Create the project directory

```bash
mkdir -p ~/cloud-cost-pulse/{dags,consumer,dbt/models/staging,dbt/models/intermediate,dbt/models/gold,dbt/tests,scripts,logs,plugins,config}
cd ~/cloud-cost-pulse
```

> 📄 **[`.env`](./.env)**

```bash
chmod 600 .env
```

The `.env` file is temporary lab material. Keep it readable only by the current user and do not commit it or expose its values in logs.

### Task 8 - Build the Airflow image

Create Dockerfile:

> 📄 **[`Dockerfile`](./Dockerfile)**

If that image tag is unavailable, use the stable Python 3 Airflow image tag available in the playground and keep the dependency list.

Create docker-compose.yml using the service definitions below. Keep database connection values in environment variables or local `.env`; replace `RDS_USER`, `RDS_PASSWORD`, and `RDS_ENDPOINT` with URL-encoded values from the database secret before starting Airflow. Do not commit real passwords.

> 📄 **[`docker-compose.yml`](./docker-compose.yml)**

Build the image:

```bash
docker compose build
```

### Task 9 - Create the local Kafka event source

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

For the missing-team test, remove `team` from the JSON. For the negative-quantity test, set `quantity` below zero. For the delayed-event test, set `event_time` well before the current date while keeping `received_at` current. For the spike, raise the payments `checkout-api` quantity to 5-10 times its normal value.

The Kafbat UI is available at `http://EC2_PUBLIC_IP:8081`; Kafka itself stays on Docker's private Compose network and does not need a public broker port.

### Task 10 - Implement the Kafka consumer

Create consumer/consumer.py:

> 📄 **[`consumer/consumer.py`](./consumer/consumer.py)**

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

### Task 11 - Create warehouse tables

Create scripts/warehouse.sql:

> 📄 **[`scripts/warehouse.sql`](./scripts/warehouse.sql)**

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

### Task 12 - Configure dbt

Create dbt/profiles.yml:

> 📄 **[`dbt/profiles.yml`](./dbt/profiles.yml)**

Create `dbt/macros/generate_schema_name.sql` so the schemas in `dbt_project.yml` are used exactly (without the target-schema prefix):

> 📄 **[`dbt/macros/generate_schema_name.sql`](./dbt/macros/generate_schema_name.sql)**

Create dbt/dbt_project.yml:

> 📄 **[`dbt/dbt_project.yml`](./dbt/dbt_project.yml)**

Create dbt/models/staging/stg_usage_events.sql:

> 📄 **[`dbt/models/staging/stg_usage_events.sql`](./dbt/models/staging/stg_usage_events.sql)**

Create dbt/models/intermediate/int_costed_usage.sql:

> 📄 **[`dbt/models/intermediate/int_costed_usage.sql`](./dbt/models/intermediate/int_costed_usage.sql)**

Create dbt/models/gold/fact_cost.sql:

> 📄 **[`dbt/models/gold/fact_cost.sql`](./dbt/models/gold/fact_cost.sql)**

The composite key makes reruns idempotent for the same event and rate-card version. When a corrected rate uses a new `rate_card_id`, dbt appends that new model run while retaining the earlier fact row.
Do not use `dbt run --full-refresh` after the fact table has version history; a full refresh rebuilds the incremental table and removes retained prior versions.

Run dbt manually:

```bash
docker compose run --rm airflow-apiserver dbt --project-dir /opt/airflow/dbt debug
docker compose run --rm airflow-apiserver dbt --project-dir /opt/airflow/dbt run
docker compose run --rm airflow-apiserver dbt --project-dir /opt/airflow/dbt test
```

### Task 13 - Add validation and quarantine

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

> 📄 **[`consumer/_common.py`](./consumer/_common.py)**

> 📄 **[`consumer/check_manifests.py`](./consumer/check_manifests.py)**

> 📄 **[`consumer/validate_batch.py`](./consumer/validate_batch.py)**

> 📄 **[`consumer/load_staging.py`](./consumer/load_staging.py)**

> 📄 **[`consumer/detect_anomalies.py`](./consumer/detect_anomalies.py)**

> 📄 **[`consumer/explain_anomalies.py`](./consumer/explain_anomalies.py)**

> 📄 **[`consumer/publish_metrics.py`](./consumer/publish_metrics.py)**

```bash
python -m py_compile consumer/consumer.py consumer/_common.py consumer/check_manifests.py consumer/validate_batch.py consumer/load_staging.py consumer/detect_anomalies.py consumer/explain_anomalies.py consumer/publish_metrics.py
```

Run the compile check before starting Airflow. The scripts intentionally fail on unreadable S3, missing state, unavailable PostgreSQL, or failed CloudWatch writes; individual malformed records are quarantined and do not stop the batch.

### Task 14 - Review deterministic anomaly detection

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

### Task 15 - Add the KodeKey adapter

Create consumer/kodekey_provider.py. Use the exact endpoint and payload format shown in the KodeKey API example:

> 📄 **[`consumer/kodekey_provider.py`](./consumer/kodekey_provider.py)**

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

### Task 16 - Create the Airflow DAG

Create dags/finops_microbatch.py:

> 📄 **[`dags/finops_microbatch.py`](./dags/finops_microbatch.py)**

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

### Task 17 - Run the end-to-end validation

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

### Task 18 - Test the failure paths

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

### Task 19 - Inject the FinOps anomaly

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

### Task 20 - Add operational checks

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

### Task 21 - Backfill and replay

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

```

---

## Files in this folder

The steps above reference these ready-to-use files (copy them onto the playground):

- [`.env`](./.env)
- [`Dockerfile`](./Dockerfile)
- [`consumer/_common.py`](./consumer/_common.py)
- [`consumer/check_manifests.py`](./consumer/check_manifests.py)
- [`consumer/consumer.py`](./consumer/consumer.py)
- [`consumer/detect_anomalies.py`](./consumer/detect_anomalies.py)
- [`consumer/explain_anomalies.py`](./consumer/explain_anomalies.py)
- [`consumer/kodekey_provider.py`](./consumer/kodekey_provider.py)
- [`consumer/load_staging.py`](./consumer/load_staging.py)
- [`consumer/publish_metrics.py`](./consumer/publish_metrics.py)
- [`consumer/validate_batch.py`](./consumer/validate_batch.py)
- [`dags/finops_microbatch.py`](./dags/finops_microbatch.py)
- [`dbt/dbt_project.yml`](./dbt/dbt_project.yml)
- [`dbt/macros/generate_schema_name.sql`](./dbt/macros/generate_schema_name.sql)
- [`dbt/models/gold/fact_cost.sql`](./dbt/models/gold/fact_cost.sql)
- [`dbt/models/intermediate/int_costed_usage.sql`](./dbt/models/intermediate/int_costed_usage.sql)
- [`dbt/models/staging/stg_usage_events.sql`](./dbt/models/staging/stg_usage_events.sql)
- [`dbt/profiles.yml`](./dbt/profiles.yml)
- [`docker-compose.yml`](./docker-compose.yml)
- [`scripts/warehouse.sql`](./scripts/warehouse.sql)
