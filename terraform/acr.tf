resource "azurerm_container_registry" "acr" {
  name                = "${var.project_name}acr${var.environment}"
  resource_group_name = data.azurerm_resource_group.rg.name
  location            = var.location
  sku                 = var.acr_sku
  admin_enabled       = false
  tags                = var.tags
}