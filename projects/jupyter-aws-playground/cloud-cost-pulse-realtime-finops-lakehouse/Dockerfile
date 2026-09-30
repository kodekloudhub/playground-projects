FROM apache/airflow:3.1.0-python3.12
USER root
RUN apt-get update && apt-get install -y --no-install-recommends gcc libpq-dev && apt-get clean && rm -rf /var/lib/apt/lists/*
USER airflow
RUN pip install --no-cache-dir dbt-postgres boto3 psycopg2-binary pandas pyarrow pydantic scikit-learn confluent-kafka requests
