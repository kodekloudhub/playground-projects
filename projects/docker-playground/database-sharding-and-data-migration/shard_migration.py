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
