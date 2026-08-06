# Look up the app pipeline SP by its client ID, so Terraform can grant it AcrPush
data "azuread_service_principal" "app_pipeline_sp" {
  client_id = var.app_pipeline_client_id
}

resource "azurerm_role_assignment" "app_pipeline_acr_push" {
  principal_id         = data.azuread_service_principal.app_pipeline_sp.object_id
  role_definition_name = "AcrPush"
  scope                = azurerm_container_registry.acr.id
}