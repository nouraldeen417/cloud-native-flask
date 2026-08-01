location            = "eastus"
project_name        = "flaskapp"
environment         = "dev"
resource_group_name = "rg-flaskapp-dev"

tags = {
  project     = "flaskapp"
  environment = "dev"
  managed_by  = "terraform"
}

# terraform.tfvars
app_pipeline_client_id = "c46ac504-a1cf-40dc-9403-275d89cba615"