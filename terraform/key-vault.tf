data "azurerm_client_config" "current" {}

resource "azurerm_key_vault" "kv" {
  name                      = "kv-${var.project_name}-${var.environment}"
  resource_group_name       = data.azurerm_resource_group.rg.name
  location                  = var.location
  tenant_id                 = data.azurerm_client_config.current.tenant_id
  sku_name                  = "standard"
  enable_rbac_authorization = true
  purge_protection_enabled  = false # false = can fully delete on teardown; set true for real prod
  tags                      = var.tags
}

# Lets YOU (running terraform locally) manage secrets in the vault
resource "azurerm_role_assignment" "kv_admin_self" {
  scope                = azurerm_key_vault.kv.id
  role_definition_name = "Key Vault Administrator"
  principal_id         = data.azurerm_client_config.current.object_id
}

# Lets AKS's Key Vault CSI addon identity READ secrets (not write)
resource "azurerm_role_assignment" "kv_reader_aks" {
  scope                = azurerm_key_vault.kv.id
  role_definition_name = "Key Vault Secrets User"
  principal_id         = azurerm_kubernetes_cluster.aks.key_vault_secrets_provider[0].secret_identity[0].object_id
}

resource "azurerm_key_vault_secret" "mysql_password" {
  name         = "mysql-admin-password"
  value        = var.mysql_admin_password
  key_vault_id = azurerm_key_vault.kv.id

  depends_on = [azurerm_role_assignment.kv_admin_self]
}