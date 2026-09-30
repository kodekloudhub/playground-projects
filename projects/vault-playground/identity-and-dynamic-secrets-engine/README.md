# Identity & Dynamic Secret Engines

**Level:** intermediate  ·  **Playground:** Vault Playground

▶ **[Launch the playground](https://kodekloud.com/playgrounds/playground-hashicorp-vault)** — open it, then copy the files below.

A [`commands.sh`](./commands.sh) with the runnable steps is included.

 — Automated Database Token Lifecycles & Dynamic Key Rotation

## Scenario
A billing service needs short-lived database credentials instead of a shared permanent password. Vault is already deployed in an active HA state, and its database secrets engine is already mounted. You must connect Vault to the local MySQL service, issue temporary read-only credentials, verify them over TCP, and revoke them during a containment exercise.

## What you'll build
You will build and audit a complete dynamic database credential workflow on a pre-configured Vault instance: verify Vault health and the existing database mount, create a dedicated MySQL account for Vault, define a bounded read-only billing role, request and test dynamic credentials over the MySQL network interface, and revoke the lease to prove containment.

## Learning objectives
By the end you will be able to:
- Audit Vault HA health and confirm a mounted database secrets engine.
- Connect Vault's database plugin to MySQL over a dedicated TCP account.
- Define a Vault role that issues least-privilege, time-bounded credentials.
- Revoke a lease and verify the temporary account is immediately unusable.

## Prerequisites
- Playground: **HashiCorp Vault** (open it before starting)
- Basic Vault CLI
- Understanding of MySQL users and grants
- Familiarity with secrets management concepts

## Architecture / overview
Vault runs in **active HA mode** on Raft storage with a pre-mounted `database/` secrets engine. Vault authenticates to **MySQL** over TCP (`127.0.0.1:3306`) using a dedicated `vault_admin` account, and the `billing-app-role` issues ephemeral `SELECT`-only MySQL users with a 5-minute default TTL. Lease revocation removes those users on demand.

## Steps

### Task 1 — Verify Vault Health and Audit the Database Mount

Confirm Vault is initialized, unsealed, responsive, and active before configuring secret injection.

1. Check Vault health:
```bash
vault status
```

Confirm that:
- `Initialized` is `true`
- `Sealed` is `false`
- Storage is `raft`
- `HA Enabled` is `true`

2. Audit the available secret engines:
```bash
vault secrets list
```

Confirm that `database/` is present. Do **not** run `vault secrets enable database` — the mount is provided by the lab.

> **Why:** A health and mount audit ensures Vault is active on Raft with the pre-enabled `database/` engine before you configure secret delivery.

### Task 2 — Provision the MySQL Administrator and Configure Vault

Create a dedicated MySQL account Vault can use over TCP, then connect Vault to the local MySQL service.

1. Create the dedicated account in MySQL:
```bash
sudo mysql <<'SQL'
CREATE USER IF NOT EXISTS 'vault_admin'@'127.0.0.1' IDENTIFIED BY 'VaultAdminPassword123!';
GRANT ALL PRIVILEGES ON *.* TO 'vault_admin'@'127.0.0.1' WITH GRANT OPTION;
FLUSH PRIVILEGES;
SQL
```

2. Configure Vault's existing database mount:
```bash
vault write database/config/production-mysql \
  plugin_name=mysql-database-plugin \
  connection_url="{{username}}:{{password}}@tcp(127.0.0.1:3306)/" \
  allowed_roles="billing-app-role" \
  username="vault_admin" \
  password="VaultAdminPassword123!"
```

3. Verify the connection from Vault:
```bash
vault read database/config/production-mysql
```

> **Why:** Local root auth often uses the Unix socket; a dedicated `127.0.0.1` account gives the database plugin an explicit network identity over TCP.

### Task 3 — Define the Ephemeral Billing Database Role

Create a Vault role that generates temporary MySQL users with read-only access and bounded leases.

1. Create the role with a five-minute default TTL and ten-minute maximum TTL:
```bash
vault write database/roles/billing-app-role \
  db_name=production-mysql \
  creation_statements="CREATE USER '{{name}}'@'%' IDENTIFIED BY '{{password}}'; GRANT SELECT ON *.* TO '{{name}}'@'%';" \
  default_ttl="300s" \
  max_ttl="600s"
```

2. Verify the role:
```bash
vault read database/roles/billing-app-role
```

> **Why:** The role is the policy boundary — Vault substitutes `{{name}}` and `{{password}}`, grants only `SELECT`, and removes the user when the lease is revoked or expires.

### Task 4 — Request and Test Dynamic Credentials

Request a temporary credential pair and prove it can authenticate to MySQL over the TCP loopback with read-only privileges.

1. Ensure `jq` is available for parsing Vault JSON output:
```bash
sudo apt-get update
sudo apt-get install -y jq
```

2. Request credentials and display the lease information:
```bash
vault read database/creds/billing-app-role
```

3. Capture the generated username, password, and lease ID for the next step:
```bash
umask 077
CREDENTIALS_JSON=$(vault read -format=json database/creds/billing-app-role)
printf 'DYNAMIC_USER=%q\n' "$(printf '%s' "$CREDENTIALS_JSON" | jq -r '.data.username')" > /home/admin/vault-dynamic-credentials.env
printf 'DYNAMIC_PASS=%q\n' "$(printf '%s' "$CREDENTIALS_JSON" | jq -r '.data.password')" >> /home/admin/vault-dynamic-credentials.env
printf 'LEASE_ID=%q\n' "$(printf '%s' "$CREDENTIALS_JSON" | jq -r '.lease_id')" >> /home/admin/vault-dynamic-credentials.env
chmod 600 /home/admin/vault-dynamic-credentials.env
source /home/admin/vault-dynamic-credentials.env
printf 'Generated user: %s\nLease: %s\n' "$DYNAMIC_USER" "$LEASE_ID"
```

4. Test authentication, grants, and read access:
```bash
source /home/admin/vault-dynamic-credentials.env
mysql -u "$DYNAMIC_USER" -p"$DYNAMIC_PASS" -h 127.0.0.1 -e "SHOW GRANTS; SHOW DATABASES;"
```

> **Why:** The credentials are leased, not permanent. A successful test shows a `GRANT SELECT` entry and no write grant, proving least-privilege access.

### Task 5 — Revoke the Lease and Verify Containment

Revoke the exact Vault lease and prove the temporary MySQL account is immediately unusable.

1. Revoke the lease captured in Task 4:
```bash
source /home/admin/vault-dynamic-credentials.env
vault lease revoke "$LEASE_ID"
```

2. Confirm the same credentials can no longer authenticate:
```bash
source /home/admin/vault-dynamic-credentials.env
if mysql -u "$DYNAMIC_USER" -p"$DYNAMIC_PASS" -h 127.0.0.1 -e "SHOW DATABASES;" >/tmp/revoked-credential-output.txt 2>&1; then
  echo "FAIL: Revoked credentials still authenticate."
  exit 1
fi
cat /tmp/revoked-credential-output.txt
```

> **Why:** Lease revocation is an incident-response control — it removes the generated user before the normal expiry, invalidating credentials that may have been exposed.

## Validation

1. Verify Vault is active, unsealed, on Raft, with the database mount:
```bash
vault status
vault secrets list | grep '^database/'
```

2. Verify the MySQL account works over TCP and the connection is configured:
```bash
mysql -h 127.0.0.1 -u vault_admin -pVaultAdminPassword123! -e 'SELECT 1'
vault read database/config/production-mysql
```

3. Verify the role uses the production connection with bounded TTLs:
```bash
vault read -field=default_ttl database/roles/billing-app-role
vault read -field=max_ttl database/roles/billing-app-role
```

4. Verify the revoked lease no longer authenticates:
```bash
source /home/admin/vault-dynamic-credentials.env
mysql -u "$DYNAMIC_USER" -p"$DYNAMIC_PASS" -h 127.0.0.1 -e 'SHOW DATABASES'
```

Expected result:
- [ ] Vault reports `Sealed false`, active HA mode, and Raft storage, with `database/` present.
- [ ] `vault_admin` authenticates over TCP and Vault reports the `mysql-database-plugin` connection allowing `billing-app-role`.
- [ ] `billing-app-role` points to `production-mysql` with `default_ttl` 300 and `max_ttl` 600.
- [ ] Dynamic credentials authenticate over TCP with `SELECT` only (no write privileges).
- [ ] After `vault lease revoke`, the same credentials fail authentication.

## References & further learning
- Vault database secrets engine: https://developer.hashicorp.com/vault/docs/secrets/databases
- Vault MySQL database plugin: https://developer.hashicorp.com/vault/docs/secrets/databases/mysql-maria
- Vault database secrets engine tutorial: https://developer.hashicorp.com/vault/tutorials/db-credentials/database-secrets
- KodeKloud course: HashiCorp Certified: Vault Associate: https://beta.kodekloud.com/learn/courses/hashicorp-certified-vault-associate-certification
