resource "aws_secretsmanager_secret" "mysql_password" {
  name = "${var.project_name}-mysql-password-${var.environment}"
  recovery_window_in_days = 0
  tags = var.tags
}

resource "aws_secretsmanager_secret_version" "mysql_password" {
  secret_id     = aws_secretsmanager_secret.mysql_password.id
  secret_string = var.mysql_admin_password
}
