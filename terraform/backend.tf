terraform {
  backend "azurerm" {
    resource_group_name  = "rg-tfstate"
    storage_account_name = "sttfstate152"
    container_name       = "tfstate"
    key                  = "flaskapp.tfstate"
    # use_oidc             = true # Authenticate using the GitHub OIDC token instead of access keys
    # use_azuread_auth     = true
  }
}