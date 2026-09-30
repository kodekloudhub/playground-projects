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
2. Use a small single-AZ instance with approximately 20 GiB encrypted storage. Before creating it, create or select a DB subnet group in the same VPC with subnets from at least two Availability Zones.

3. Place it in the same VPC as EC2.
4. Create cloud-cost-pulse-rds-sg.
5. Allow TCP 5432 from cloud-cost-pulse-ec2-sg only.
6. Keep public access disabled when EC2 can reach the private endpoint.
7. Record the endpoint, port, master user, and password. Wait until the DB instance status is Available before connecting. The two CREATE DATABASE statements are first-run commands; on reruns, check pg_database first and skip databases that already exist.

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

Create docker-compose.yml using the service definitions below. Keep database connection values in environment variables or local `.env`; replace `RDS_USER`, `RDS_PASSWORD`, and `RDS_ENDPOINT` with URL-encoded values from the database secret before starting Airflow. Do not commit real passwords.

Build the image:

### Task 9 — Create the local Kafka event source

Kafka runs locally in Docker on the EC2 host. You will create its topic and publish test events in the Kafbat Kafka UI. Start Kafka and its browser UI:

Open `http://EC2_PUBLIC_IP:8081`. Select the `finops-local` cluster. In the UI, open **Topics**, choose **Create topic**, and enter:

- Topic name: `finops-usage`
- Partitions: `3`
- Replication factor: `1`

Open `finops-usage`, select **Messages**, then choose **Produce message** (the label may appear as **Produce**). Leave the key blank or use the event ID as the key. Paste the JSON below into the message value and send it:

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

Start the local consumer:

From another SSH session, verify uploads:

The consumer must preserve each source `event_id` and `batch_id`. Downstream loading must use `INSERT ... ON CONFLICT (event_id) DO NOTHING`; repeated records are counted once and any duplicate is written to `audit.data_quality_issues`.

Each S3 manifest also stores `records_read`, `records_failed`, and `batch_upload_seconds`. `records_read` counts Kafka messages successfully returned to the consumer. `records_failed` counts Kafka message errors and JSON decoding failures; schema or business-rule rejections are counted separately as quarantined pipeline rows.

### Task 11 — Create warehouse tables

Create scripts/warehouse.sql:

Run it:

Insert a rate card and budget using psql:

### Task 12 — Configure dbt

Create dbt/profiles.yml:

Create `dbt/macros/generate_schema_name.sql` so the schemas in `dbt_project.yml` are used exactly (without the target-schema prefix):

Create dbt/dbt_project.yml:

Create dbt/models/staging/stg_usage_events.sql:

Create dbt/models/intermediate/int_costed_usage.sql:

Create dbt/models/gold/fact_cost.sql:

The composite key makes reruns idempotent for the same event and rate-card version. When a corrected rate uses a new `rate_card_id`, dbt appends that new model run while retaining the earlier fact row.
Do not use `dbt run --full-refresh` after the fact table has version history; a full refresh rebuilds the incremental table and removes retained prior versions.

Run dbt manually:

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

### Task 16 — Create the Airflow DAG

Create dags/finops_microbatch.py:

Every helper must log dag_id, task_id, run_id, batch_id, input row count, output row count, affected S3 prefix, database tables, and elapsed time.

Initialize and start:

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

Confirm CloudWatch receives all nine `CloudCostPulse` metrics listed in Task 20, including the three `consumer.*` metrics.

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
