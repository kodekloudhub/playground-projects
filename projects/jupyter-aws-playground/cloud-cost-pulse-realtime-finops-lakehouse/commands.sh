#!/usr/bin/env bash
set -euo pipefail

Verify the role:

The caller identity should show an assumed role based on `iam_role_ec2`.

### Task 4 — Create the S3 lake

Run on EC2:

Verify:

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

Create separate logical databases:

### Task 6 — Store secrets in Secrets Manager

Create the database secret locally on EC2, use it once, then remove the file:

Create the KodeKey secret using the exact API values from KodeKey:

Verify only secret names:

### Task 7 — Create the project directory

The `.env` file is temporary lab material. Keep it readable only by the current user and do not commit it or expose its values in logs.

### Task 8 — Build the Airflow image

Create Dockerfile:

If that image tag is unavailable, use the stable Python 3 Airflow image tag available in the playground and keep the dependency list.

Create docker-compose.yml:

Replace the database placeholders with URL-encoded values from the database secret. Do not commit the Compose file with real passwords.

Build the image:

### Task 9 — Create the local Kafka event source

Kafka runs locally in Docker on the EC2 host. Create the topic and use this JSON shape for producer messages:

Create these test cases with a local producer:

1. Normal events for payments, search, and analytics.
2. A duplicate event with the same event_id.
3. An event with no team.
4. An event with a negative quantity.
5. A delayed event with an old event_time.
6. A 5x to 10x payments/checkout-api spike.

Start the local broker and create the topic:

Send a synthetic event directly to the local topic:

Use the same command with different `event_id`, `team`, `quantity`, and
`event_time` values to create the duplicate, malformed, delayed, and spike
cases listed above.

### Task 10 — Implement the Kafka consumer

Create consumer/consumer.py:

Start the local consumer:

From another SSH session, verify uploads:

### Task 11 — Create warehouse tables

Create scripts/warehouse.sql:

Run it:

Insert a rate card and budget using psql:

### Task 12 — Configure dbt

Create dbt/profiles.yml:

Create dbt/dbt_project.yml:

Create dbt/models/staging/stg_usage_events.sql:

Create dbt/models/intermediate/int_costed_usage.sql:

Create dbt/models/gold/fact_cost.sql:

Run dbt manually:

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

Every helper must log dag_id, task_id, run_id, batch_id, input row count, output row count, affected S3 prefix, database tables, and elapsed time.

Initialize and start:

Open Airflow at http://EC2_PUBLIC_IP:8080. Unpause finops_microbatch and trigger one run manually.

### Task 17 — Run the end-to-end validation

1. Send normal Kafka events for three windows.
2. Confirm a manifest appears under raw/manifests/.
3. Trigger finops_microbatch.
4. Confirm validation, loading, dbt, tests, anomaly detection, and KodeKey tasks complete.
5. Query the warehouse:

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
