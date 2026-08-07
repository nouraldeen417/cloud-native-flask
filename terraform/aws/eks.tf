data "aws_iam_role" "eks_cluster_role" {
  name = var.eks_cluster_role_name
}

resource "aws_eks_cluster" "main" {
  name                      = "eks-${var.project_name}-${var.environment}"
  role_arn                  = data.aws_iam_role.eks_cluster_role.arn
  version                   = var.eks_kubernetes_version
  enabled_cluster_log_types = ["api", "audit", "authenticator", "controllerManager", "scheduler"]
  vpc_config {
    subnet_ids              = aws_subnet.private[*].id
    endpoint_public_access  = true
    endpoint_private_access = true
  }

  tags = var.tags
}

resource "aws_eks_node_group" "main" {
  cluster_name    = aws_eks_cluster.main.name
  node_group_name = "ng-${var.project_name}-${var.environment}"
  node_role_arn   = data.aws_iam_role.eks_cluster_role.arn # Learner Lab: same role used for both cluster and nodes unless your guide lists a separate node role
  subnet_ids      = aws_subnet.private[*].id               # nodes in private subnets, matching your earlier choice

  scaling_config {
    desired_size = var.eks_node_count
    max_size     = var.eks_node_count + 1
    min_size     = var.eks_node_count
  }

  instance_types = [var.eks_node_instance_type]

  depends_on = [aws_eks_cluster.main]
}
resource "helm_release" "secrets_store_csi_driver" {
  name             = "csi-secrets-store"
  repository       = "https://kubernetes-sigs.github.io/secrets-store-csi-driver/charts"
  chart            = "secrets-store-csi-driver"
  namespace        = "kube-system"

  depends_on = [aws_eks_cluster.main]
}

resource "helm_release" "aws_secrets_provider" {
  name             = "secrets-provider-aws"
  repository       = "https://aws.github.io/secrets-store-csi-driver-provider-aws"
  chart            = "secrets-store-csi-driver-provider-aws"
  namespace        = "kube-system"

  depends_on = [helm_release.secrets_store_csi_driver]
}