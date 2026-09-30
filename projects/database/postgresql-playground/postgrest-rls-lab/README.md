# PostgREST Multi-Tenant Security with PostgreSQL RLS

**Level:** advanced  ·  **Playground:** PostgreSQL Playground

▶ **[Launch the playground](https://kodekloud.com/playgrounds/playground-postgresql)** — open it, then copy the files below.

A [`commands.sh`](./commands.sh) with the runnable steps is included.

```powershell
---
# ─── Metadata (read by the playground for listing & filtering) ───
id: postgrest-rls-lab
title: PostgREST Multi-Tenant Security with PostgreSQL RLS
playground: PostgreSQL
playground_link: https://kodekloud.com/playgrounds/playground-postgresql
difficulty: advanced
estimated_minutes: 45
tags:
  - postgresql
  - postgrest
  - row-level security
  - multi-tenancy
  - jwt
skills:
  - PostgreSQL role-based authorization
  - PostgREST JWT authentication
  - row-level security policy design
  - tenant-isolation testing
prerequisites:
  - Basic SQL and PostgreSQL administration
  - Basic REST and curl usage
  - Familiarity with JSON Web Tokens
---

# PostgREST Multi-Tenant Security with PostgreSQL RLS

## Scenario

A project-management platform stores tasks for many customer workspaces in one PostgreSQL database. A serious data-isolation bug would allow a user from one workspace to read or write another workspace’s tasks. You will build the authorization boundary in PostgreSQL, expose it through PostgREST, and prove that JWT workspace claims control both reads and writes.

## What you'll build

You will create a PostgREST API backed by PostgreSQL, with separate database roles for anonymous requests and tenant requests. The `api.tasks` table will use PostgreSQL Row-Level Security (RLS) to compare each row’s `workspace_id` with the `workspace_id` claim in the caller’s JWT. You will then verify anonymous denial, tenant-specific reads, cross-tenant write rejection, and an authorized tenant write.

## Learning objectives

By the end you will be able to:

- Configure PostgREST to switch database roles from a JWT `role` claim.
- Read JWT claims from PostgreSQL transaction-scoped settings.
- Protect a shared table with RLS `USING` and `WITH CHECK` policies.
- Test both read isolation and write isolation with repeatable HTTP requests.
- Distinguish SQL privileges from row-level authorization.

## Prerequisites

- Playground: **PostgreSQL** (open it before starting)
- A PostgreSQL account with permission to create roles, schemas, and tables
- A shell with `curl`, `openssl`, `base64`, `jq`, and `psql`

## Steps

### Task 1 — Prepare the PostgreSQL Playground

Set connection variables without placing the database password in a file or command history. Use the username and password supplied by the PostgreSQL Playground.

```bash
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
```

### Task 2 — Create the Tenant-Aware Database Security Model

Generate an authenticator password and a JWT signing secret. The secret is deliberately generated for this lab session; in production, store it in a secret manager and rotate it.

```bash
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
```

### Task 3 — Install and Configure PostgREST

Use the existing PostgREST installation when available. Otherwise, download the official Linux binary. The pinned version keeps the lab reproducible.

```bash
if ! command -v postgrest >/dev/null 2>&1; then
  POSTGREST_VERSION=12.2.12
  curl -fsSLo /tmp/postgrest.tar.xz \
    "https://github.com/PostgREST/postgrest/releases/download/v${POSTGREST_VERSION}/postgrest-v${POSTGREST_VERSION}-linux-static-x86_64.tar.xz"
  tar -xJf /tmp/postgrest.tar.xz -C /tmp
  install -m 0755 /tmp/postgrest /usr/local/bin/postgrest
fi

postgrest --help | head -n 5

cat <<EOF > postgrest.conf
db-uri = "postgres://authenticator:${AUTHENTICATOR_PASSWORD}@${PGHOST}:${PGPORT}/${PGDATABASE}"
db-schemas = "api"
db-anon-role = "web_anon"
jwt-secret = "${JWT_SECRET}"
server-host = "0.0.0.0"
server-port = 3000
EOF
```

### Task 4 — Create Tenant JWTs and Start the API

Create short-lived HS256 tokens containing the database role and tenant workspace. The signing secret must exactly match `jwt-secret` in `postgrest.conf`. This uses OpenSSL and shell utilities, so Python is not required.

```bash
b64url() {
  printf '%s' "$1" | base64 -w 0 | tr '+/' '-_' | tr -d '='
}

make_jwt() {
  workspace="$1"
  header=$(b64url '{"alg":"HS256","typ":"JWT"}')
  payload=$(b64url "{\"role\":\"tenant_user\",\"workspace_id\":\"${workspace}\",\"exp\":$(( $(date +%s) + 3600 ))}")
  unsigned="${header}.${payload}"
  signature=$(printf '%s' "$unsigned" | \
    openssl dgst -sha256 -mac HMAC -macopt "hexkey:${JWT_SECRET}" -binary | \
    base64 -w 0 | tr '+/' '-_' | tr -d '=')
  printf '%s.%s' "$unsigned" "$signature"
}

export ALPHA_JWT="$(make_jwt ws_alpha)"
export BETA_JWT="$(make_jwt ws_beta)"

if [ -f postgrest.pid ] && kill -0 "$(cat postgrest.pid)" 2>/dev/null; then
  kill "$(cat postgrest.pid)"
  sleep 2
fi

postgrest postgrest.conf > postgrest.log 2>&1 &
echo $! > postgrest.pid

until curl -fsS http://localhost:3000/ >/dev/null; do
  sleep 2
done

curl -sS http://localhost:3000/
```

### Task 5 — Prove Read Isolation

Run the anonymous, Alpha, and Beta requests. Save the responses so you can inspect exactly which rows were returned.

```bash
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
```

> **Success check:** The anonymous request is denied, Alpha sees only `ws_alpha`, and Beta sees only `ws_beta`.

### Task 6 — Prove Write Isolation and Authorized Writes

First try to inject a Beta row with an Alpha JWT. Then submit a valid Alpha row and fetch the feed again.

```bash
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
```

> **Success check:** The cross-tenant insert returns HTTP 403 or another denied response containing an RLS/permission error. The valid Alpha insert succeeds and immediately appears only in Alpha’s feed.

## Validation

Run these final checks to inspect the database authorization model and confirm the API is still running.

```bash
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
```

Expected result:

- [ ] PostgREST is reachable on port 3000.
- [ ] `api.tasks` has row security and forced row security enabled.
- [ ] The policy contains both a visibility condition and an insert/update check.
- [ ] Alpha results contain only `ws_alpha`.
- [ ] Beta results contain only `ws_beta`.
- [ ] Anonymous access and cross-tenant writes are denied.

## References & further learning

- [PostgREST authentication and JWT role switching](https://docs.postgrest.org/en/latest/references/auth.html)
- [PostgREST installation and configuration](https://postgrest.org/en/stable/explanations/install.html)
- [PostgreSQL row security policies](https://www.postgresql.org/docs/17/ddl-rowsecurity.html)
- [PostgreSQL CREATE POLICY reference](https://www.postgresql.org/docs/17/sql-createpolicy.html)
```
