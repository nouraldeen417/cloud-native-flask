variable "location" {
  description = "Azure region for all resources"
  type        = string
}

variable "project_name" {
  description = "Short name used as prefix for all resource names"
  type        = string
}

variable "environment" {
  description = "Environment tag (dev/test/prod)"
  type        = string
  default     = "dev"
}

variable "resource_group_name" {
  description = "Name of the resource group"
  type        = string
}

variable "tags" {
  description = "Common tags applied to all resources"
  type        = map(string)
  default     = {}
}
/*--------------------------Log Analytics Workspace---------------------------*/
variable "log_analytics_sku" {
  description = "SKU for the Log Analytics Workspace"
  type        = string
  default     = "PerGB2018"
}

variable "log_analytics_retention_days" {
  description = "Log retention in days"
  type        = number
  default     = 30
}
/*--------------------------ACR---------------------------*/
variable "acr_sku" {
  description = "SKU for the Azure Container Registry"
  type        = string
  default     = "Basic"
}
/*--------------------------AKS---------------------------*/
variable "aks_kubernetes_version" {
  description = "Kubernetes version for AKS"
  type        = string
  default     = "1.34.5"
}

variable "aks_node_count" {
  description = "Number of nodes in the default node pool"
  type        = number
  default     = 1
}

variable "aks_vm_size" {
  description = "VM size for AKS nodes"
  type        = string
  default     = "Standard_B2s_v2"
}

/*--------------------------Ingress---------------------------*/
variable "ingress_nginx_chart_version" {
  description = "Helm chart version for ingress-nginx"
  type        = string
  default     = "4.11.0"
}
/*--------------------------Argo CD---------------------------*/
variable "argocd_chart_version" {
  description = "Helm chart version for Argo CD"
  type        = string
  default     = "7.3.0"
}

/*--------------------------MySql---------------------------*/
variable "mysql_admin_username" {
  description = "Admin username for MySQL Flexible Server"
  type        = string
  default     = "mysqladmin"
}

variable "mysql_admin_password" {
  description = "Admin password for MySQL Flexible Server"
  type        = string
  sensitive   = true
}

variable "mysql_sku_name" {
  description = "SKU for MySQL Flexible Server"
  type        = string
  default     = "B_Standard_B1ms"
}

variable "mysql_version" {
  description = "MySQL major version"
  type        = string
  default     = "8.0.21"
}

variable "mysql_storage_gb" {
  description = "Storage size in GB"
  type        = number
  default     = 20
}

variable "mysql_database_name" {
  description = "Name of the application database"
  type        = string
  default     = "BucketList"
}

/*--------------------------VNET---------------------------*/
variable "vnet_address_space" {
  description = "Address space for the VNet"
  type        = string
  default     = "10.0.0.0/16"
}

variable "aks_subnet_prefix" {
  description = "Address prefix for the AKS subnet"
  type        = string
  default     = "10.0.0.0/20"
}

variable "aks_service_cidr" {
  description = "CIDR for Kubernetes internal services (must NOT overlap vnet_address_space)"
  type        = string
  default     = "10.1.0.0/16"
}

variable "aks_dns_service_ip" {
  description = "IP within service_cidr reserved for cluster DNS"
  type        = string
  default     = "10.1.0.10"
}


variable "app_pipeline_client_id" {
  description = "Client ID of the app pipeline Service Principal (needs AcrPush on ACR)"
  type        = string
}


/*--------------------------DataBaseDisasterRecovery---------------------------*/
variable "aws_lambda_function_url" {
  description = "The public AWS Lambda Function URL that returns a pre-signed S3 upload URL"
  type        = string
}
