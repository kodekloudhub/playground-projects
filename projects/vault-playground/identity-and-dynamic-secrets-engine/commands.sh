#!/usr/bin/env bash
set -euo pipefail

vault status

vault secrets list

sudo mysql <<'SQL'
CREATE USER IF NOT EXISTS 'vault_admin'@'127.0.0.1' IDENTIFIED BY 'VaultAdminPassword123!';
GRANT ALL PRIVILEGES ON *.* TO 'vault_admin'@'127.0.0.1' WITH GRANT OPTION;
FLUSH PRIVILEGES;
SQL

vault write database/config/production-mysql \
  plugin_name=mysql-database-plugin \
  connection_url="{{username}}:{{password}}@tcp(127.0.0.1:3306)/" \
  allowed_roles="billing-app-role" \
  username="vault_admin" \
  password="VaultAdminPassword123!"

vault read database/config/production-mysql

vault write database/roles/billing-app-role \
  db_name=production-mysql \
  creation_statements="CREATE USER '{{name}}'@'%' IDENTIFIED BY '{{password}}'; GRANT SELECT ON *.* TO '{{name}}'@'%';" \
  default_ttl="300s" \
  max_ttl="600s"

vault read database/roles/billing-app-role

sudo apt-get update
sudo apt-get install -y jq

vault read database/creds/billing-app-role

umask 077
CREDENTIALS_JSON=$(vault read -format=json database/creds/billing-app-role)
printf 'DYNAMIC_USER=%q\n' "$(printf '%s' "$CREDENTIALS_JSON" | jq -r '.data.username')" > /home/admin/vault-dynamic-credentials.env
printf 'DYNAMIC_PASS=%q\n' "$(printf '%s' "$CREDENTIALS_JSON" | jq -r '.data.password')" >> /home/admin/vault-dynamic-credentials.env
printf 'LEASE_ID=%q\n' "$(printf '%s' "$CREDENTIALS_JSON" | jq -r '.lease_id')" >> /home/admin/vault-dynamic-credentials.env
chmod 600 /home/admin/vault-dynamic-credentials.env
source /home/admin/vault-dynamic-credentials.env
printf 'Generated user: %s\nLease: %s\n' "$DYNAMIC_USER" "$LEASE_ID"

source /home/admin/vault-dynamic-credentials.env
mysql -u "$DYNAMIC_USER" -p"$DYNAMIC_PASS" -h 127.0.0.1 -e "SHOW GRANTS; SHOW DATABASES;"

source /home/admin/vault-dynamic-credentials.env
vault lease revoke "$LEASE_ID"

source /home/admin/vault-dynamic-credentials.env
if mysql -u "$DYNAMIC_USER" -p"$DYNAMIC_PASS" -h 127.0.0.1 -e "SHOW DATABASES;" >/tmp/revoked-credential-output.txt 2>&1; then
  echo "FAIL: Revoked credentials still authenticate."
  exit 1
fi
cat /tmp/revoked-credential-output.txt

vault status
vault secrets list | grep '^database/'

mysql -h 127.0.0.1 -u vault_admin -pVaultAdminPassword123! -e 'SELECT 1'
vault read database/config/production-mysql

vault read -field=default_ttl database/roles/billing-app-role
vault read -field=max_ttl database/roles/billing-app-role

source /home/admin/vault-dynamic-credentials.env
mysql -u "$DYNAMIC_USER" -p"$DYNAMIC_PASS" -h 127.0.0.1 -e 'SHOW DATABASES'
