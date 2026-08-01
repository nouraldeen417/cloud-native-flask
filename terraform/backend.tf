terraform {
  backend "azurerm" {
    resource_group_name  = "rg-tfstate"
    storage_account_name = "sttfstate152"
    container_name       = "tfstate"
    key                  = "flaskapp.tfstate"
  }
}