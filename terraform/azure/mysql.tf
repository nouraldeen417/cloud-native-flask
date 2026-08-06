resource "azurerm_mysql_flexible_server" "mysql" {
  name                   = "mysql-${var.project_name}-${var.environment}"
  resource_group_name    = data.azurerm_resource_group.rg.name
  location               = var.location
  administrator_login    = var.mysql_admin_username
  administrator_password = var.mysql_admin_password
  sku_name               = var.mysql_sku_name
  version                = var.mysql_version
  storage {
    size_gb = var.mysql_storage_gb
  }
  lifecycle {
    ignore_changes = [zone]
  }
  tags = var.tags
}

resource "azurerm_mysql_flexible_database" "app_db" {
  name                = var.mysql_database_name
  resource_group_name = data.azurerm_resource_group.rg.name
  server_name         = azurerm_mysql_flexible_server.mysql.name
  charset             = "utf8mb4"
  collation           = "utf8mb4_unicode_ci"
}

# Allows Azure resources (including AKS) to reach this server.
# Special rule: start=0.0.0.0 end=0.0.0.0 = "Allow public access from any Azure service"
# This is the time-constrained tradeoff — see README note below.
resource "azurerm_mysql_flexible_server_firewall_rule" "allow_azure_services" {
  name                = "AllowAzureServices"
  resource_group_name = data.azurerm_resource_group.rg.name
  server_name         = azurerm_mysql_flexible_server.mysql.name
  start_ip_address    = "0.0.0.0"
  end_ip_address      = "0.0.0.0"
}

resource "azurerm_monitor_diagnostic_setting" "mysql_diagnostics" {
  name                       = "diag-mysql-${var.project_name}-${var.environment}"
  target_resource_id         = azurerm_mysql_flexible_server.mysql.id
  log_analytics_workspace_id = azurerm_log_analytics_workspace.law.id

  enabled_log {
    category = "MySqlAuditLogs"
  }
  enabled_log {
    category = "MySqlSlowLogs"
  }

  metric {
    category = "AllMetrics"
  }
}

# Audit logging must also be explicitly turned on at the server parameter level —
# the diagnostic setting above only ships logs *if* the server is generating them.
resource "azurerm_mysql_flexible_server_configuration" "audit_log_enabled" {
  name                = "audit_log_enabled"
  resource_group_name = data.azurerm_resource_group.rg.name
  server_name         = azurerm_mysql_flexible_server.mysql.name
  value               = "ON"
}

resource "azurerm_mysql_flexible_server_configuration" "audit_log_events" {
  name                = "audit_log_events"
  resource_group_name = data.azurerm_resource_group.rg.name
  server_name         = azurerm_mysql_flexible_server.mysql.name
  value               = "CONNECTION,DML,DDL"
}