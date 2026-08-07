output "ecr_repository_url" {
  value = aws_ecr_repository.flask_app.repository_url
}
output "eks_cluster_name" {
  value = aws_eks_cluster.main.name
}
output "eks_kube_config_command" {
  value = "aws eks update-kubeconfig --region ${var.aws_region} --name ${aws_eks_cluster.main.name}"
}
output "rds_endpoint" {
  value = aws_db_instance.mysql.address
}
output "secrets_manager_secret_arn" {
  value = aws_secretsmanager_secret.mysql_password.arn
}
