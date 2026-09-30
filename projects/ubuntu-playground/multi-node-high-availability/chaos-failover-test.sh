#!/bin/bash
set -euo pipefail

restore_worker() {
    ssh node02 'sudo systemctl start nginx' >/dev/null 2>&1 || true
}
trap restore_worker EXIT

echo "INITIALIZING HIGH AVAILABILITY FAILOVER TEST"
echo "[STAGE 1] VERIFYING BOTH WORKERS"
for i in 1 2 3 4; do
    curl -fsS http://localhost | grep -oE 'WEB WORKER [AB]'
    sleep 0.2
done

echo "[STAGE 2] STOPPING NODE02"
ssh node02 'sudo systemctl stop nginx'
sleep 5

echo "[STAGE 3] VERIFYING FAILOVER TO NODE03"
for i in 1 2 3 4; do
    response=$(curl -fsS http://localhost)
    echo "$response" | grep -q 'WEB WORKER B'
    echo "$response" | grep -oE 'WEB WORKER [AB]'
    sleep 0.2
done

echo "[STAGE 4] RESTORING NODE02"
ssh node02 'sudo systemctl start nginx'
sleep 3
curl -fsS http://node02 | grep -q 'WEB WORKER A'
echo "FAILOVER_TEST_PASSED"
