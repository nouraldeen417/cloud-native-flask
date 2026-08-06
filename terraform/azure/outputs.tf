output "resource_group_name" {
  description = "Name of the resource group"
  value       = data.azurerm_resource_group.rg.name
}

output "acr_login_server" {
  description = "Login server URL for ACR (used in GitHub Actions build/push and K8s image references)"
  value       = azurerm_container_registry.acr.login_server
}

output "acr_name" {
  description = "ACR name (needed for AcrPush role assignment you'll do manually later)"
  value       = azurerm_container_registry.acr.name
}

output "aks_cluster_name" {
  description = "AKS cluster name"
  value       = azurerm_kubernetes_cluster.aks.name
}

output "aks_kube_config_command" {
  description = "Run this to fetch kubeconfig locally"
  value       = "az aks get-credentials --resource-group ${data.azurerm_resource_group.rg.name} --name ${azurerm_kubernetes_cluster.aks.name}"
}

output "aks_kubelet_identity_object_id" {
  description = "Object ID of the AKS Kubelet Identity (has AcrPull on ACR)"
  value       = azurerm_kubernetes_cluster.aks.kubelet_identity[0].object_id
}

output "mysql_fqdn" {
  description = "MySQL Flexible Server FQDN (use as DB host in K8s ConfigMap)"
  value       = azurerm_mysql_flexible_server.mysql.fqdn
}

output "mysql_database_name" {
  description = "Application database name"
  value       = azurerm_mysql_flexible_database.app_db.name
}

output "key_vault_name" {
  description = "Key Vault name"
  value       = azurerm_key_vault.kv.name
}

output "key_vault_uri" {
  description = "Key Vault URI (used in SecretProviderClass manifest)"
  value       = azurerm_key_vault.kv.vault_uri
}

output "key_vault_tenant_id" {
  description = "Tenant ID (used in SecretProviderClass manifest)"
  value       = data.azurerm_client_config.current.tenant_id
}

output "log_analytics_workspace_id" {
  description = "Log Analytics Workspace ID (used for KQL queries later)"
  value       = azurerm_log_analytics_workspace.law.workspace_id
}

output "vnet_name" {
  description = "VNet name"
  value       = azurerm_virtual_network.vnet.name
}

output "aks_subnet_id" {
  description = "AKS subnet ID (needed if you add a MySQL private endpoint later)"
  value       = azurerm_subnet.aks_subnet.id
}