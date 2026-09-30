#!/usr/bin/env bash
set -euo pipefail

### Task 2 — Create the Tenant-Aware Database Security Model

Generate an authenticator password and a JWT signing secret. The secret is deliberately generated for this lab session; in production, store it in a secret manager and rotate it.

### Task 3 — Install and Configure PostgREST

Use the existing PostgREST installation when available. Otherwise, download the official Linux binary. The pinned version keeps the lab reproducible.

### Task 4 — Create Tenant JWTs and Start the API

Create short-lived HS256 tokens containing the database role and tenant workspace. The signing secret must exactly match `jwt-secret` in `postgrest.conf`. This uses OpenSSL and shell utilities, so Python is not required.

### Task 5 — Prove Read Isolation

Run the anonymous, Alpha, and Beta requests. Save the responses so you can inspect exactly which rows were returned.

> **Success check:** The anonymous request is denied, Alpha sees only `ws_alpha`, and Beta sees only `ws_beta`.

### Task 6 — Prove Write Isolation and Authorized Writes

First try to inject a Beta row with an Alpha JWT. Then submit a valid Alpha row and fetch the feed again.

> **Success check:** The cross-tenant insert returns HTTP 403 or another denied response containing an RLS/permission error. The valid Alpha insert succeeds and immediately appears only in Alpha’s feed.

## Validation

Run these final checks to inspect the database authorization model and confirm the API is still running.

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
