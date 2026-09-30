#!/usr/bin/env bash
set -euo pipefail

apt-get update
apt-get install -y curl openssl jq postgresql-client xz-utils

export PGHOST=localhost
export PGPORT=5432
export PGUSER=bob
export PGDATABASE=postgres
read -rsp "PostgreSQL password: " PGPASSWORD
export PGPASSWORD
printf '\n'

psql -c 'select current_user, current_database(), version();'

export AUTHENTICATOR_PASSWORD="$(openssl rand -hex 24)"
export JWT_SECRET="$(openssl rand -hex 32)"

PGPASSWORD="$PGPASSWORD" psql -v ON_ERROR_STOP=1 <<SQL
DO \$\$
BEGIN
  IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname = 'authenticator') THEN
    CREATE ROLE authenticator LOGIN PASSWORD '${AUTHENTICATOR_PASSWORD}';
  ELSE
    ALTER ROLE authenticator WITH LOGIN PASSWORD '${AUTHENTICATOR_PASSWORD}';
  END IF;

  IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname = 'web_anon') THEN
    CREATE ROLE web_anon NOLOGIN;
  END IF;

  IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname = 'tenant_user') THEN
    CREATE ROLE tenant_user NOLOGIN;
  END IF;
END
\$\$;

DROP SCHEMA IF EXISTS api CASCADE;
CREATE SCHEMA api;

CREATE TABLE api.tasks (
  id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  workspace_id text NOT NULL CHECK (workspace_id IN ('ws_alpha', 'ws_beta')),
  title text NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now()
);

INSERT INTO api.tasks (workspace_id, title) VALUES
  ('ws_alpha', 'Provision application network'),
  ('ws_alpha', 'Configure tenant observability'),
  ('ws_beta', 'Rotate database credentials'),
  ('ws_beta', 'Review backup retention');

CREATE OR REPLACE FUNCTION api.current_workspace_id()
RETURNS text
LANGUAGE sql
STABLE
AS \$fn\$
  SELECT NULLIF(current_setting('request.jwt.claims', true), '')::json ->> 'workspace_id';
\$fn\$;

GRANT USAGE ON SCHEMA api TO tenant_user;
GRANT SELECT, INSERT, UPDATE, DELETE ON api.tasks TO tenant_user;
GRANT USAGE, SELECT ON SEQUENCE api.tasks_id_seq TO tenant_user;

GRANT web_anon TO authenticator;
GRANT tenant_user TO authenticator;

ALTER TABLE api.tasks ENABLE ROW LEVEL SECURITY;
ALTER TABLE api.tasks FORCE ROW LEVEL SECURITY;

CREATE POLICY tenant_task_isolation ON api.tasks
  FOR ALL
  TO tenant_user
  USING (workspace_id = api.current_workspace_id())
  WITH CHECK (workspace_id = api.current_workspace_id());

REVOKE ALL ON api.tasks FROM web_anon;
SQL

if ! command -v postgrest >/dev/null 2>&1; then
  POSTGREST_VERSION=12.2.12
  curl -fsSLo /tmp/postgrest.tar.xz \
    "https://github.com/PostgREST/postgrest/releases/download/v${POSTGREST_VERSION}/postgrest-v${POSTGREST_VERSION}-linux-static-x86_64.tar.xz"
  tar -xJf /tmp/postgrest.tar.xz -C /tmp
  install -m 0755 /tmp/postgrest /usr/local/bin/postgrest
fi

postgrest --help | head -n 5

ANON_STATUS=$(curl -sS -o /tmp/anon.json -w '%{http_code}' \
  http://localhost:3000/tasks)
ALPHA_STATUS=$(curl -sS -o /tmp/alpha.json -w '%{http_code}' \
  -H "Authorization: Bearer ${ALPHA_JWT}" \
  'http://localhost:3000/tasks?select=id,workspace_id,title&order=id')
BETA_STATUS=$(curl -sS -o /tmp/beta.json -w '%{http_code}' \
  -H "Authorization: Bearer ${BETA_JWT}" \
  'http://localhost:3000/tasks?select=id,workspace_id,title&order=id')

echo "anonymous HTTP status: ${ANON_STATUS}"
echo "alpha HTTP status: ${ALPHA_STATUS}"
echo "beta HTTP status: ${BETA_STATUS}"
echo "Alpha response:"
cat /tmp/alpha.json
echo
echo "Beta response:"
cat /tmp/beta.json
echo

test "$(jq '[.[] | select(.workspace_id != "ws_alpha")] | length' /tmp/alpha.json)" -eq 0
test "$(jq '[.[] | select(.workspace_id != "ws_beta")] | length' /tmp/beta.json)" -eq 0
test "$(jq 'length' /tmp/alpha.json)" -gt 0
test "$(jq 'length' /tmp/beta.json)" -gt 0
echo 'Read isolation verified: Alpha and Beta can only see their own rows.'

BAD_STATUS=$(curl -sS -o /tmp/cross_tenant.json -w '%{http_code}' \
  -X POST http://localhost:3000/tasks \
  -H "Authorization: Bearer ${ALPHA_JWT}" \
  -H 'Content-Type: application/json' \
  -H 'Prefer: return=representation' \
  -d '{"workspace_id":"ws_beta","title":"Cross-tenant injection attempt"}')

GOOD_STATUS=$(curl -sS -o /tmp/authorized.json -w '%{http_code}' \
  -X POST http://localhost:3000/tasks \
  -H "Authorization: Bearer ${ALPHA_JWT}" \
  -H 'Content-Type: application/json' \
  -H 'Prefer: return=representation' \
  -d '{"workspace_id":"ws_alpha","title":"Provision Database Backup Locks"}')

echo "Cross-tenant insert HTTP status: ${BAD_STATUS}"
cat /tmp/cross_tenant.json
echo
echo "Authorized insert HTTP status: ${GOOD_STATUS}"
cat /tmp/authorized.json
echo

curl -sS \
  -H "Authorization: Bearer ${ALPHA_JWT}" \
  'http://localhost:3000/tasks?select=id,workspace_id,title&order=id' \
  | tee /tmp/alpha-after-write.json
echo

grep -Eiq 'row-level security|permission denied' /tmp/cross_tenant.json
test "$(jq 'length' /tmp/authorized.json)" -eq 1
test "$(jq -r '.[0].workspace_id' /tmp/authorized.json)" = 'ws_alpha'
test "$(jq '[.[] | select(.title == "Provision Database Backup Locks")] | length' /tmp/alpha-after-write.json)" -eq 1
test "$(jq '[.[] | select(.workspace_id != "ws_alpha")] | length' /tmp/alpha-after-write.json)" -eq 0
echo 'Write isolation verified: cross-tenant insert rejected and authorized write visible.'

curl -fsS http://localhost:3000/ >/dev/null && echo "PostgREST is reachable"

PGPASSWORD="$PGPASSWORD" psql -At -c \
  "SELECT schemaname || '.' || tablename, rowsecurity, forcerowsecurity
   FROM pg_tables WHERE schemaname = 'api' AND tablename = 'tasks';"

PGPASSWORD="$PGPASSWORD" psql -At -c \
  "SELECT policyname, roles, cmd, qual, with_check
   FROM pg_policies WHERE schemaname = 'api' AND tablename = 'tasks';"

printf 'Alpha rows: '
curl -fsS -H "Authorization: Bearer ${ALPHA_JWT}" \
  'http://localhost:3000/tasks?select=workspace_id' | grep -o 'ws_alpha' | wc -l

printf 'Beta rows: '
curl -fsS -H "Authorization: Bearer ${BETA_JWT}" \
  'http://localhost:3000/tasks?select=workspace_id' | grep -o 'ws_beta' | wc -l
