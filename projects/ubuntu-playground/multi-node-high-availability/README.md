# Multi-Node High Availability

**Level:** intermediate  ·  **Playground:** Ubuntu Playground

▶ **[Launch the playground](https://kodekloud.com/playgrounds/playground-ubuntu-20-04-multi-node)** — open it, then copy the files below.

## Files in this project
- [`chaos-failover-test.sh`](./chaos-failover-test.sh)

> Copy these into your playground session (or `git clone` this repo and `cd` here).

A [`commands.sh`](./commands.sh) with the runnable steps is included.

## Scenario
An internal web application must remain available when one runtime node fails. You are responsible for turning three Linux nodes into a small high-availability web platform: `node01` is the ingress router, while `node02` and `node03` serve the application.

## What you'll build
You will map a three-node topology and establish SSH trust, deploy two independently identifiable Nginx web workers, configure HAProxy on `node01` as a health-checked round-robin load balancer, run an automated chaos failover test that survives a worker outage, and audit the final operational state of the platform.

## Learning objectives
By the end you will be able to:
- Establish DNS resolution and SSH trust across a multi-node environment.
- Deploy distinct backend web workers to make load-balancer behavior observable.
- Configure HAProxy with active health checks and a statistics endpoint.
- Prove service continuity by injecting a worker failure and verifying recovery.

## Prerequisites
- Playground: **Ubuntu 20.04 Multi-Node** (open it before starting)
- Basic Linux CLI and SSH
- Understanding of load balancing concepts
- Familiarity with systemd services

> **Password:** Whenever SSH or `sudo` prompts for a password on `node01`, `node02`, or `node03`, enter `caleston123`. You connect as the `bob` user.

## Architecture / overview
`node01` runs **HAProxy** as the ingress router on port `80`, with a statistics page on port `9000`. It balances round-robin across two **Nginx workers**: `node02` (Web Worker A) and `node03` (Web Worker B). Active HTTP health checks remove a worker from rotation when it fails and re-admit it on recovery.

## Steps

### Task 1 — Map the Topology and Establish Connectivity

Confirm the internal addresses of all three nodes and register worker SSH keys so later automation runs without interactive host-key prompts. Run these from `node01`:

```bash
getent hosts node01
getent hosts node02
getent hosts node03

mkdir -p ~/.ssh
chmod 700 ~/.ssh
touch ~/.ssh/known_hosts
ssh-keyscan node02 node03 >> ~/.ssh/known_hosts
chmod 600 ~/.ssh/known_hosts

ssh node02 'hostname && echo SSH_TO_NODE02_OK'
ssh node03 'hostname && echo SSH_TO_NODE03_OK'
```

> **Note:** On the first connection to `node02` or `node03`, enter the password `caleston123`.

> **Why:** Name resolution and SSH trust must work before you can configure services on the workers remotely. Use `ssh-keygen -F node02` to confirm a host key is registered.

### Task 2 — Provision the Distributed Web Worker Fleet

Install Nginx on both workers and give each a unique landing page so traffic distribution can be observed. From `node01`, configure Web Worker A:

```bash
ssh node02 "sudo apt-get update && sudo apt-get install -y nginx && echo '<h1>CLUSTER NODE STATUS: OPERATIONAL [WEB WORKER A]</h1>' | sudo tee /var/www/html/index.html && sudo systemctl restart nginx"
```

Configure Web Worker B:

```bash
ssh node03 "sudo apt-get update && sudo apt-get install -y nginx && echo '<h1>CLUSTER NODE STATUS: OPERATIONAL [WEB WORKER B]</h1>' | sudo tee /var/www/html/index.html && sudo systemctl restart nginx"
```

Verify both workers from `node01`:

```bash
curl -fsS http://node02 | grep 'WEB WORKER A'
curl -fsS http://node03 | grep 'WEB WORKER B'
```

> **Note:** SSH and `sudo` will prompt for the password `caleston123` on each worker.

> **Why:** A load balancer only provides useful redundancy when backends are independently reachable; distinct markers let you identify which worker answered each request.

### Task 3 — Deploy the HAProxy Ingress Load Balancer

Configure `node01` to distribute HTTP traffic across both workers and remove unhealthy ones automatically.

1. Install HAProxy on `node01`:
```bash
sudo apt-get update
sudo apt-get install -y haproxy
```

2. Replace the configuration with this complete manifest:
```bash
sudo tee /etc/haproxy/haproxy.cfg >/dev/null <<'EOF'
global
    log /dev/log local0
    log /dev/log local1 notice
    daemon

defaults
    log global
    mode http
    option httplog
    option dontlognull
    timeout connect 5s
    timeout client 30s
    timeout server 30s

frontend http_ingress_router
    bind *:80
    mode http
    default_backend application_worker_fleet

backend application_worker_fleet
    mode http
    balance roundrobin
    option httpchk GET /
    server app-worker-A node02:80 check inter 2000 rise 2 fall 2
    server app-worker-B node03:80 check inter 2000 rise 2 fall 2

listen stats
    bind *:9000
    mode http
    stats enable
    stats uri /
    stats refresh 5s
EOF
```

3. Validate and enable the service:
```bash
sudo haproxy -c -f /etc/haproxy/haproxy.cfg
sudo systemctl restart haproxy
sudo systemctl enable haproxy
curl -fsS http://localhost | grep -E 'WEB WORKER [AB]'
curl -fsS http://localhost:9000/ | grep -qi 'HAProxy'
```

> **Why:** The frontend accepts client traffic and the backend selects workers round-robin; the HTTP check with rise/fall thresholds controls when a worker is admitted or removed. Always validate the config before restarting.

### Task 4 — Execute the Chaos Failover and Recovery Test

Prove that traffic continues through `node03` when `node02` is stopped, then restore `node02`.

1. Create the harness as a copy-pasteable file and run it:
```bash
cat <<'EOF' > chaos-failover-test.sh
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
EOF
chmod +x chaos-failover-test.sh
./chaos-failover-test.sh
```

2. Review the output and confirm Stage 3 contains only `WEB WORKER B`.

> **Note:** The remote `sudo` commands on `node02` use the password `caleston123`.

> **Why:** The test uses the same health checks that protect production traffic. Allow enough time for the `fall` threshold to mark the backend down, and the shell `trap` restores the worker even if a check fails.

### Task 5 — Audit the Operational High-Availability Layer

Collect a final snapshot proving the ingress node, both workers, and both HAProxy endpoints are healthy. Run from `node01`:

```bash
echo "=== NODE HEALTH ==="
for node in node01 node02 node03; do
    ssh "$node" "hostname; uptime -p"
done

echo "=== WORKER HEALTH ==="
curl -fsS http://node02 | grep 'WEB WORKER A'
curl -fsS http://node03 | grep 'WEB WORKER B'

echo "=== INGRESS HEALTH ==="
sudo systemctl is-active haproxy
curl -fsS http://localhost | grep -oE 'WEB WORKER [AB]'
curl -fsS http://localhost:9000/ | grep -qi HAProxy
```

> **Note:** `sudo` on `node01` uses the password `caleston123`.

> **Why:** A high-availability configuration is not complete until its runtime state is observable — the audit confirms service state, backend reachability, routing, and the statistics endpoint.

## Validation

1. Verify topology resolution and SSH trust:
```bash
for node in node01 node02 node03; do getent hosts "$node"; done
ssh-keygen -F node02 -f ~/.ssh/known_hosts
ssh-keygen -F node03 -f ~/.ssh/known_hosts
```

2. Verify both workers are active with distinct markers:
```bash
curl -fsS http://node02 | grep 'WEB WORKER A'
curl -fsS http://node03 | grep 'WEB WORKER B'
```

3. Verify HAProxy is valid, active, balanced, and exposing stats:
```bash
sudo haproxy -c -f /etc/haproxy/haproxy.cfg
systemctl is-active haproxy
curl -fsS http://localhost | grep -E 'WEB WORKER [AB]'
curl -fsS http://localhost:9000/ | grep -i HAProxy
```

4. Verify the failover harness ran and left node02 restored:
```bash
grep 'FAILOVER_TEST_PASSED' chaos-failover-test.sh
ssh node02 'systemctl is-active nginx'
```

Expected result:
- [ ] `node01`, `node02`, and `node03` resolve, and both workers are trusted in `known_hosts`.
- [ ] `node02` returns the Web Worker A marker and `node03` returns Web Worker B.
- [ ] HAProxy is valid, active, enabled, round-robin balanced, and serving the stats page on port 9000.
- [ ] During the chaos test, requests continue through Web Worker B while node02 is stopped.
- [ ] `FAILOVER_TEST_PASSED` is printed and node02 Nginx is restored to the pool.

## References & further learning
- HAProxy Configuration Manual: https://docs.haproxy.org/3.0/configuration.html
- HAProxy Health Checks: https://www.haproxy.com/documentation/haproxy-configuration-tutorials/reliability/health-checks/
- Nginx Ubuntu documentation: https://documentation.ubuntu.com/server/how-to/web-services/install-nginx/
- KodeKloud course: Linux Foundation Certified System Administrator (LFCS): https://kodekloud.com/courses/linux-foundation-certified-system-administrator-lfcs/
