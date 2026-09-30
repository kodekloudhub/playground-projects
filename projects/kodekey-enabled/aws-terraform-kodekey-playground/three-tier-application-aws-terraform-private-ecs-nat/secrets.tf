resource "aws_secretsmanager_secret" "db_password" {
  name                    = "${var.environment}/nova/db-password"
  recovery_window_in_days = 0
}

resource "aws_secretsmanager_secret_version" "db_password" {
  secret_id     = aws_secretsmanager_secret.db_password.id
  secret_string = var.db_password
}

resource "aws_secretsmanager_secret" "kodekey_api_key" {
  name                    = "${var.environment}/nova/kodekey-api-key"
  recovery_window_in_days = 0
}

resource "aws_secretsmanager_secret_version" "kodekey_api_key" {
  secret_id     = aws_secretsmanager_secret.kodekey_api_key.id
  secret_string = var.kodekey_api_key
}

resource "aws_secretsmanager_secret" "searxng_secret_key" {
  name                    = "${var.environment}/nova/searxng-secret-key"
  recovery_window_in_days = 0
}

resource "aws_secretsmanager_secret_version" "searxng_secret_key" {
  secret_id     = aws_secretsmanager_secret.searxng_secret_key.id
  secret_string = var.searxng_secret_key
}

resource "aws_secretsmanager_secret" "database_url" {
  name                    = "${var.environment}/nova/database-url"
  recovery_window_in_days = 0
}

resource "aws_secretsmanager_secret_version" "database_url" {
  secret_id     = aws_secretsmanager_secret.database_url.id
  secret_string = "postgres://${var.db_user}:${var.db_password}@${aws_db_instance.rds_db.address}:5432/${var.db_name}?sslmode=require"
}
