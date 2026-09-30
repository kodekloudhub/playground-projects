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
