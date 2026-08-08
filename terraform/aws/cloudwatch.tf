resource "helm_release" "fluent_bit" {
  name             = "aws-for-fluent-bit"
  repository       = "https://aws.github.io/eks-charts"
  chart            = "aws-for-fluent-bit"
  namespace        = "amazon-cloudwatch"
  create_namespace = true

  set {
    name  = "hostNetwork"
    value = "true"
  }

  set {
    name  = "cloudWatch.enabled"
    value = "true"
  }
  set {
    name  = "cloudWatch.region"
    value = var.aws_region
  }
  set {
    name  = "cloudWatch.logGroupName"
    value = "/aws/containerinsights/eks-${var.project_name}-${var.environment}/application"
  }

  depends_on = [aws_eks_cluster.main, helm_release.cloudwatch_agent]
}