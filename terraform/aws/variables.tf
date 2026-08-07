variable "aws_region" {
  description = "AWS region for all resources"
  type        = string
  default     = "us-east-1"
}

variable "project_name" {
  description = "Short name used as prefix for all resource names"
  type        = string
  default     = "flaskapp"
}

variable "environment" {
  description = "Environment tag"
  type        = string
  default     = "dev"
}

variable "tags" {
  description = "Common tags applied to all resources"
  type        = map(string)
  default = {
    project    = "flaskapp"
    managed_by = "terraform"
  }
}

/*--------------------------VPC---------------------------*/
variable "vpc_cidr" {
  description = "CIDR block for the VPC"
  type        = string
  default     = "10.10.0.0/16"
}

variable "availability_zones" {
  description = "AZs to spread subnets across"
  type        = list(string)
  default     = ["us-east-1a", "us-east-1b"]
}
/*--------------------------Roles---------------------------*/
variable "eks_cluster_role_name" {
  description = "Pre-existing Learner Lab EKS cluster IAM role name (not created by Terraform)"
  type        = string
  default     = "LabRole"
}
/*--------------------------EKS---------------------------*/
variable "eks_kubernetes_version" {
  description = "Kubernetes version for EKS"
  type        = string
  default     = "1.34"
}

variable "eks_node_count" {
  description = "Desired number of worker nodes"
  type        = number
  default     = 1
}

variable "eks_node_instance_type" {
  description = "EC2 instance type for worker nodes (must be nano/micro/small/medium/large per Learner Lab restriction)"
  type        = string
  default     = "t3.medium"
}

/*--------------------------RDS---------------------------*/
variable "rds_mysql_version" {
  description = "MySQL engine version for RDS"
  type        = string
  default     = "8.0.45"
}

variable "rds_instance_class" {
  description = "RDS instance class (Learner Lab: check allowed sizes)"
  type        = string
  default     = "db.t3.micro"
}

variable "rds_storage_gb" {
  description = "Allocated storage in GB"
  type        = number
  default     = 20
}

variable "mysql_database_name" {
  description = "Application database name"
  type        = string
  default     = "BucketList"
}

variable "mysql_admin_username" {
  description = "RDS admin username"
  type        = string
  default     = "mysqladmin"
}

variable "mysql_admin_password" {
  description = "RDS admin password"
  type        = string
  sensitive   = true
}
/*--------------------------Helm---------------------------*/
variable "ingress_nginx_chart_version" {
  description = "The version of the ingress-nginx Helm chart to deploy."
  type        = string
  default     = "4.15.1"
}

variable "argocd_chart_version" {
  description = "The version of the Argo CD Helm chart to deploy."
  type        = string
  default     = "8.2.6"
}
