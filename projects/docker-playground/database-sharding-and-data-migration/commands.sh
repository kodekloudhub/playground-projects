#!/usr/bin/env bash
set -euo pipefail

sudo apt update
sudo apt install python3 python3-pip python3-venv -y

docker network create sharding-net

docker compose up -d

docker ps

python3 -m venv .venv
source .venv/bin/activate

pip install -r requirements.txt

python3 shard_migration.py

cat parity_verification.txt

docker network ls | grep sharding-net

docker ps --format "{{.Names}} - {{.Ports}}"

cat parity_verification.txt
