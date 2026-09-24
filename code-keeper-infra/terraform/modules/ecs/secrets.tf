# =====================================================
# AWS SECRETS MANAGER
# =====================================================

resource "aws_secretsmanager_secret" "app" {
  name                    = "${var.environment}/app-secrets"
  recovery_window_in_days = 0

  tags = {
    Name        = "${var.environment}-app-secrets"
    Environment = var.environment
  }
}

resource "aws_secretsmanager_secret_version" "app" {
  secret_id = aws_secretsmanager_secret.app.id

  secret_string = jsonencode({
    INVENTORY_DB_USER     = var.inventory_db_user
    INVENTORY_DB_PASSWORD = var.inventory_db_password
    INVENTORY_DB_NAME     = var.inventory_db_name

    BILLING_DB_USER     = var.billing_db_user
    BILLING_DB_PASSWORD = var.billing_db_password
    BILLING_DB_NAME     = var.billing_db_name

    RABBITMQ_USER     = var.rabbitmq_user
    RABBITMQ_PASSWORD = var.rabbitmq_password
    RABBITMQ_QUEUE    = var.rabbitmq_queue
  })
}
