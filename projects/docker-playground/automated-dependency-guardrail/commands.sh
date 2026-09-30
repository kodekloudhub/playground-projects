#!/usr/bin/env bash
set -euo pipefail

docker version

docker network create guardrail-net
docker volume create gitea-data
docker volume create gitea-runner-data

docker pull docker.gitea.com/gitea:1.22.6
docker pull docker.io/gitea/act_runner:0.2.11

docker run -d \
  --name gitea \
  --restart unless-stopped \
  --network guardrail-net \
  -p 3000:3000 \
  -v gitea-data:/data \
  -e GITEA__database__DB_TYPE=sqlite3 \
  -e GITEA__repository__DEFAULT_BRANCH=main \
  -e GITEA__service__DISABLE_REGISTRATION=true \
  -e GITEA__security__INSTALL_LOCK=true \
  -e GITEA__actions__ENABLED=true \
  -e GITEA__server__ROOT_URL=http://localhost:3000/ \
  docker.gitea.com/gitea:1.22.6

until curl -fsS http://localhost:3000/user/login >/dev/null; do
  sleep 2
done

docker exec --user git gitea gitea admin user create \
  --username security-admin \
  --password gitea2026 \
  --email admin@xfusioncorp.internal \
  --admin \
  --must-change-password=false \
  --config /data/gitea/conf/app.ini

RUNNER_TOKEN=$(docker exec --user git gitea gitea actions generate-runner-token \
  --config /data/gitea/conf/app.ini | tr -d '[:space:]')

docker run -d \
  --name gitea-runner \
  --restart unless-stopped \
  --network guardrail-net \
  -v gitea-runner-data:/data \
  -v /tmp/guardrail-runner-config.yaml:/config.yaml:ro \
  -v /var/run/docker.sock:/var/run/docker.sock \
  -e CONFIG_FILE=/config.yaml \
  -e GITEA_INSTANCE_URL=http://gitea:3000 \
  -e GITEA_RUNNER_REGISTRATION_TOKEN="$RUNNER_TOKEN" \
  -e GITEA_RUNNER_NAME=guardrail-runner \
  -e GITEA_RUNNER_LABELS="ubuntu-latest:docker://catthehacker/ubuntu:act-latest" \
  docker.io/gitea/act_runner:0.2.11

docker ps --filter name=gitea
curl -I http://localhost:3000/user/login
docker exec gitea-runner grep -A5 '^container:' /config.yaml
docker exec gitea-runner grep -o \
  'ubuntu-latest:docker://catthehacker/ubuntu:act-latest' \
  /data/.runner
docker logs gitea-runner --tail 30

docker ps --filter name=gitea
curl -I http://localhost:3000/user/login

curl -fsS -u security-admin:gitea2026 \
  http://localhost:3000/api/v1/repos/security-admin/dependency-guardrail

git clone http://security-admin:gitea2026@localhost:3000/security-admin/dependency-guardrail.git /tmp/dg
grep -- '--severity HIGH,CRITICAL' /tmp/dg/.gitea/workflows/main.yaml
grep -- '--exit-code 1' /tmp/dg/.gitea/workflows/main.yaml

curl -fsS -u security-admin:gitea2026 \
  "http://localhost:3000/api/v1/repos/security-admin/dependency-guardrail/actions/runs?branch=main"
