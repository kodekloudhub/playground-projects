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
