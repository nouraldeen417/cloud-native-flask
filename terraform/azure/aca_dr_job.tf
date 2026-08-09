# Container App Environment required to host the job
resource "azurerm_container_app_environment" "main" {
  name                       = "cae-${var.project_name}-${var.environment}"
  location                   = var.location
  resource_group_name        = data.azurerm_resource_group.rg.name
  log_analytics_workspace_id = azurerm_log_analytics_workspace.law.id
}

# Container App Scheduled Job for Nightly MySQL DR Backups
resource "azurerm_container_app_job" "mysql_s3_backup" {
  name                         = "job-mysql-s3-dr-backup"
  location                     = var.location
  resource_group_name          = data.azurerm_resource_group.rg.name
  container_app_environment_id = azurerm_container_app_environment.main.id
  replica_timeout_in_seconds   = 1800 # Allows the backup to run for up to 30 minutes
  replica_retry_limit          = 1    # If it fails, retry exactly 1 time
  # Triggers every night at 2:00 AM UTC
  schedule_trigger_config {
    cron_expression = "30 2 * * *"
    parallelism     = 1
  }

  # SECRETS: Securely inject password to keep it hidden in Azure Portal UI
  secret {
    name  = "mysql-password"
    value = var.mysql_admin_password
  }

  template {
    container {
      name   = "dr-backup-runner"
      image  = "alpine:3.20"
      cpu    = 0.5
      memory = "1Gi"

      command = [
        "/bin/sh", "-c",
        <<-EOF
          # 1. Install required minimal tools
          apk add --no-cache mysql-client curl jq gzip
          export MYSQL_PWD="$DB_PASS"
          # 2. Query AWS Lambda for a short-lived pre-signed upload URL
          RESPONSE=$(curl -s "$LAMBDA_FUNCTION_URL")
          UPLOAD_URL=$(echo "$RESPONSE" | jq -r .upload_url)

          if [ -z "$UPLOAD_URL" ] || [ "$UPLOAD_URL" = "null" ]; then
            echo "Error: Failed to fetch pre-signed URL from AWS Lambda."
            exit 1
          fi

          # 3. Dump and compress database
          BACKUP_FILE="backup.sql.gz"
          mysqldump -h $DB_HOST \
                    -u $DB_USER \
                    --ssl \
                    --single-transaction \
                    --quick \
                    --routines \
                    $DB_NAME | gzip > $BACKUP_FILE

          # 4. Upload compressed backup directly to AWS S3 via HTTP PUT
          curl -X PUT \
               -H "Content-Type: application/x-gzip" \
               --upload-file $BACKUP_FILE \
               "$UPLOAD_URL"

          echo "Database backup successfully uploaded to AWS S3!"
        EOF
      ]

      # Non-sensitive variables mapping directly to your DB variable definitions
      env {
        name  = "LAMBDA_FUNCTION_URL"
        value = var.aws_lambda_function_url
      }
      env {
        name = "DB_HOST"
        # Update 'azurerm_mysql_flexible_server.mysql' if your resource block uses a different name
        value = azurerm_mysql_flexible_server.mysql.fqdn
      }
      env {
        name  = "DB_USER"
        value = var.mysql_admin_username
      }
      env {
        name  = "DB_NAME"
        value = var.mysql_database_name
      }

      # Sensitive database password reference from Azure Container App secrets
      env {
        name        = "DB_PASS"
        secret_name = "mysql-password"
      }
    }
  }
}
