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