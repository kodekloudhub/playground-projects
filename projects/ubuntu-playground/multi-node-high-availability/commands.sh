#!/usr/bin/env bash
set -euo pipefail

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

ssh node02 "sudo apt-get update && sudo apt-get install -y nginx && echo '<h1>CLUSTER NODE STATUS: OPERATIONAL [WEB WORKER A]</h1>' | sudo tee /var/www/html/index.html && sudo systemctl restart nginx"

ssh node03 "sudo apt-get update && sudo apt-get install -y nginx && echo '<h1>CLUSTER NODE STATUS: OPERATIONAL [WEB WORKER B]</h1>' | sudo tee /var/www/html/index.html && sudo systemctl restart nginx"

curl -fsS http://node02 | grep 'WEB WORKER A'
curl -fsS http://node03 | grep 'WEB WORKER B'

sudo apt-get update
sudo apt-get install -y haproxy

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

sudo haproxy -c -f /etc/haproxy/haproxy.cfg
sudo systemctl restart haproxy
sudo systemctl enable haproxy
curl -fsS http://localhost | grep -E 'WEB WORKER [AB]'
curl -fsS http://localhost:9000/ | grep -qi 'HAProxy'

chmod +x chaos-failover-test.sh
./chaos-failover-test.sh

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

for node in node01 node02 node03; do getent hosts "$node"; done
ssh-keygen -F node02 -f ~/.ssh/known_hosts
ssh-keygen -F node03 -f ~/.ssh/known_hosts

curl -fsS http://node02 | grep 'WEB WORKER A'
curl -fsS http://node03 | grep 'WEB WORKER B'

sudo haproxy -c -f /etc/haproxy/haproxy.cfg
systemctl is-active haproxy
curl -fsS http://localhost | grep -E 'WEB WORKER [AB]'
curl -fsS http://localhost:9000/ | grep -i HAProxy

grep 'FAILOVER_TEST_PASSED' chaos-failover-test.sh
ssh node02 'systemctl is-active nginx'
