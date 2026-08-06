resource "azurerm_log_analytics_workspace" "law" {
  name                = "log-${var.project_name}-${var.environment}"
  resource_group_name = data.azurerm_resource_group.rg.name
  location            = var.location
  sku                 = var.log_analytics_sku
  retention_in_days   = var.log_analytics_retention_days
  tags                = var.tags
}