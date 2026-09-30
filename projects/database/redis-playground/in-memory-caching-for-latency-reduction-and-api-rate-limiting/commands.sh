#!/usr/bin/env bash
set -euo pipefail

apt-get update && apt-get install -y python3-flask python3-redis python3-requests

python3 app.py &

redis-cli -h localhost -p 6379

# 1. Verify the Python web server is listening on port 8000
netstat -tlnp | grep 8000

# 2. Check if the Redis server is actively accepting connections
redis-cli ping
