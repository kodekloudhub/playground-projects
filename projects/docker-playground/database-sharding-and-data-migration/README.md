# Database Sharding and Data Migration

**Level:** advanced  ·  **Playground:** Docker Playground

▶ **[Launch the playground](https://kodekloud.com/playgrounds/playground-docker)** — open it, then copy the files below.

## Files in this project
- [`docker-compose.yml`](./docker-compose.yml)
- [`init-monolith.sql`](./init-monolith.sql)
- [`init-shard.sql`](./init-shard.sql)
- [`requirements.txt`](./requirements.txt)
- [`shard_migration.py`](./shard_migration.py)

> Copy these into your playground session (or `git clone` this repo and `cd` here).

A [`commands.sh`](./commands.sh) with the runnable steps is included.

## Scenario
A fast-growing ride-sharing platform started with a single, centralized relational database container managing millions of historical user profiles using alphanumeric UUID keys. As transactional volume spiked, this single database monolith began suffering severe query latency and CPU exhaustion. The Tech Lead has ordered a structural migration: you must break apart this existing monolithic database and horizontally shard its historical records across two brand-new, isolated database containers. Because the primary keys are UUID strings, standard integer modulo math will fail; you must use a consistent cryptographic hashing algorithm in Python to split the records evenly without risking data loss. To simulate this environment, you will first provision the legacy infrastructure before executing the live migration.

## What you'll build
You will provision a simulated legacy monolithic database container packed with un-sharded production data alongside two empty database containers (Shard 0 and Shard 1) on a local Docker network. Then, you must write and execute an automated Python migration script that securely extracts the historical records from the monolith, programmatically converts each user's UUID string into a deterministic numerical shard assignment using an MD5 or SHA-256 hash-modulo loop, and streams the data blocks into their new target database containers.

## Learning objectives
By the end you will be able to:
- Deploy multi-node database architectures using Docker Compose and Docker networks.
- Design target schemas for horizontally sharded relational databases.
- Programmatically map alphanumeric UUIDs to shard nodes using consistent cryptographic hashing.
- Execute a zero-data-loss database migration and run decentralized scatter-gather SQL queries.

## Prerequisites
- Playground: **Docker** (open it before starting)
- Basic Docker CLI and Python knowledge

## Steps

### Task 1 — Install Prerequisites & Define Target Schema

1. Install Python and required tools:
```bash
sudo apt update
sudo apt install python3 python3-pip python3-venv -y
```

2. Add the SQL schema to `init-shard.sql`:
```bash
cat << 'EOF' > init-shard.sql
CREATE TABLE user_profiles (
    id UUID PRIMARY KEY,
    full_name VARCHAR(100),
    created_at TIMESTAMP
);
EOF
```
> **Why:** Before deploying containers, you need to install Python tools and define the identical table structures that will receive migrated data for both target shards.

### Task 2 — Deploy Shard Infrastructure

1. Add the monolith initialization SQL:
```bash
cat << 'EOF' > init-monolith.sql
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
EOF
```

2. Create the Docker network:
```bash
docker network create sharding-net
```

3. Add the Docker Compose configuration:
```bash
cat << 'EOF' > docker-compose.yml
version: '3.8'

services:
  monolith-db:
    image: postgres:15-alpine
    environment:
      POSTGRES_USER: admin
      POSTGRES_PASSWORD: password
      POSTGRES_DB: rideshare
    ports:
      - "5430:5432"
    volumes:
      - ./init-monolith.sql:/docker-entrypoint-initdb.d/init.sql
    networks:
      - sharding-net

  shard-0-db:
    image: postgres:15-alpine
    environment:
      POSTGRES_USER: admin
      POSTGRES_PASSWORD: password
      POSTGRES_DB: rideshare_shard0
    ports:
      - "5431:5432"
    volumes:
      - ./init-shard.sql:/docker-entrypoint-initdb.d/init.sql
    networks:
      - sharding-net

  shard-1-db:
    image: postgres:15-alpine
    environment:
      POSTGRES_USER: admin
      POSTGRES_PASSWORD: password
      POSTGRES_DB: rideshare_shard1
    ports:
      - "5432:5432"
    volumes:
      - ./init-shard.sql:/docker-entrypoint-initdb.d/init.sql
    networks:
      - sharding-net

networks:
  sharding-net:
    external: true
EOF
```

4. Start the containers:
```bash
docker compose up -d
```
> **Why:** You deploy the complete infrastructure containing the legacy monolithic database alongside the two new shard containers, linked together on a shared Docker network for communication.

### Task 3 — Configure Dependencies

Specify Python dependencies for the migration script:
```bash
cat << 'EOF' > requirements.txt
psycopg2-binary
EOF
```
> **Why:** The Python migration script requires the PostgreSQL driver (`psycopg2-binary`) to successfully establish connections to the database instances.

### Task 4 — Create Migration Script

Create the Python migration script:
```bash
cat << 'EOF' > shard_migration.py
import psycopg2
import psycopg2.extras
import hashlib
import time
import os

# --- Database Connection Configurations ---
DB_CONFIGS = {
    'monolith': {"host": "localhost", "port": 5430, "user": "admin", "password": "password", "dbname": "rideshare"},
    'shard0': {"host": "localhost", "port": 5431, "user": "admin", "password": "password", "dbname": "rideshare_shard0"},
    'shard1': {"host": "localhost", "port": 5432, "user": "admin", "password": "password", "dbname": "rideshare_shard1"}
}

def get_connection(config_key):
    return psycopg2.connect(**DB_CONFIGS[config_key])

def get_shard_id(uuid_str, num_shards=2):
    """
    Converts an alphanumeric UUID string into a deterministic numerical shard assignment 
    using an MD5 hash-modulo loop.
    """
    hash_hex = hashlib.md5(uuid_str.encode('utf-8')).hexdigest()
    return int(hash_hex, 16) % num_shards

def migrate_data():
    print("Starting Data Extraction & Shard Routing...")

    conn_mono = get_connection('monolith')
    conn_s0 = get_connection('shard0')
    conn_s1 = get_connection('shard1')

    cur_mono = conn_mono.cursor(cursor_factory=psycopg2.extras.DictCursor)
    cur_s0 = conn_s0.cursor()
    cur_s1 = conn_s1.cursor()

    insert_query = "INSERT INTO user_profiles (id, full_name, created_at) VALUES (%s, %s, %s)"
    cur_mono.execute("SELECT id, full_name, created_at FROM user_profiles")

    batch_s0 = []
    batch_s1 = []
    processed = 0

    while True:
        records = cur_mono.fetchmany(100) # Fetching in smaller blocks for 500 rows
        if not records:
            break

        for row in records:
            uuid_str = str(row['id'])
            shard_id = get_shard_id(uuid_str)
            record_tuple = (row['id'], row['full_name'], row['created_at'])

            if shard_id == 0:
                batch_s0.append(record_tuple)
            else:
                batch_s1.append(record_tuple)

            processed += 1

    if batch_s0:
        psycopg2.extras.execute_batch(cur_s0, insert_query, batch_s0)
    if batch_s1:
        psycopg2.extras.execute_batch(cur_s1, insert_query, batch_s1)

    conn_s0.commit()
    conn_s1.commit()

    print(f"Migration Complete! Processed {processed} historical records.")
    cur_mono.close(); cur_s0.close(); cur_s1.close()
    conn_mono.close(); conn_s0.close(); conn_s1.close()

def audit_parity():
    print("\nExecuting Post-Migration Parity Audit...")
    conn_mono = get_connection('monolith')
    conn_s0 = get_connection('shard0')
    conn_s1 = get_connection('shard1')

    def get_count(conn):
        cur = conn.cursor()
        cur.execute("SELECT COUNT(*) FROM user_profiles")
        count = cur.fetchone()[0]
        cur.close()
        return count

    mono_count = get_count(conn_mono)
    s0_count = get_count(conn_s0)
    s1_count = get_count(conn_s1)
    combined = s0_count + s1_count

    match = (mono_count == combined)
    status = "IDENTICAL (Zero data loss detected)" if match else "FAILED (Data mismatch)"

    # Write the verification file
    report_filename = "parity_verification.txt"
    with open(report_filename, "w") as f:
        f.write("--- Data Parity Verification Report ---\n")
        f.write(f"Monolith Rows: {mono_count}\n")
        f.write(f"Shard 0 Rows:  {s0_count}\n")
        f.write(f"Shard 1 Rows:  {s1_count}\n")
        f.write(f"Combined Rows: {combined}\n")
        f.write("-" * 39 + "\n")
        f.write(f"Result: {status}\n")

    # Output detailed parity to terminal
    print(f"Monolith Rows: {mono_count}")
    print(f"Shard 0 Rows:  {s0_count}")
    print(f"Shard 1 Rows:  {s1_count}")
    print(f"Combined Shard Rows: {combined}")
    print(f"Verification file generated: ./{report_filename}")

    if match:
        print("Parity Audit PASSED.")
    else:
        print("Parity Audit FAILED.")

    conn_mono.close(); conn_s0.close(); conn_s1.close()

def scatter_gather_query():
    print("\nExecuting Decentralized Scatter-Gather Query...")
    start_time = time.time()

    conn_s0 = get_connection('shard0')
    conn_s1 = get_connection('shard1')

    query = "SELECT COUNT(*) FROM user_profiles WHERE created_at >= NOW() - INTERVAL '30 days'"

    def fetch_shard_result(conn):
        cur = conn.cursor()
        cur.execute(query)
        res = cur.fetchone()[0]
        cur.close()
        return res

    res_s0 = fetch_shard_result(conn_s0)
    res_s1 = fetch_shard_result(conn_s1)

    total_active_users = res_s0 + res_s1
    execution_time = time.time() - start_time

    print(f"Total users registered in the last 30 days (Unified Analytic): {total_active_users}")
    print(f"Query completed in {execution_time:.4f} seconds.")

    conn_s0.close(); conn_s1.close()

if __name__ == "__main__":
    migrate_data()
    audit_parity()
    scatter_gather_query()
EOF
```
> **Why:** Standard integer modulo math fails on alphanumeric UUIDs. This script establishes connections, implements an MD5 hash-modulo loop for deterministic routing, and automates both the extraction and the downstream parity audits.

### Task 5 — Execute Migration & Validate

1. Verify containers are running:
```bash
docker ps
```

2. Create and activate virtual environment:
```bash
python3 -m venv .venv
source .venv/bin/activate
```

3. Install dependencies:
```bash
pip install -r requirements.txt
```

4. Run the migration script:
```bash
python3 shard_migration.py
```

5. Review the resulting data parity:
```bash
cat parity_verification.txt
```
> **Why:** This runs the full pipeline—installing dependencies inside an isolated environment and kicking off the automated routing logic to securely transfer and verify the data across shards.

## Validation
Run the following commands to confirm your architecture is working as intended and the data was migrated securely:

1. Check network configuration:
```bash
docker network ls | grep sharding-net
```

2. Check container status:
```bash
docker ps --format "{{.Names}} - {{.Ports}}"
```

3. Check the data parity audit results:
```bash
cat parity_verification.txt
```

Expected result:
- [ ] The `sharding-net` network exists.
- [ ] The legacy monolithic database container is successfully provisioned alongside the two new target shard containers (`shard-0-db` and `shard-1-db`), exposing ports `5430`, `5431`, and `5432`.
- [ ] Output from the execution displays `IDENTICAL (Zero data loss detected)`, confirming that the combined row count of Shard 0 and Shard 1 exactly matches the total row count of the original monolithic table.
- [ ] The terminal output from the script run confirmed a successful decentralized scatter-gather SQL read query executed across both sharded containers.

## References & further learning
- Docker Networking: https://docs.docker.com/network/
- PostgreSQL Partitioning & Sharding: https://www.postgresql.org/docs/current/ddl-partitioning.html
- KodeKloud course: Docker Training Course for the Absolute Beginner: https://kodekloud.com/courses/docker-training-course-for-the-absolute-beginner/
