resource "helm_release" "cloudwatch_agent" {
  name             = "aws-cloudwatch-metrics"
  repository       = "https://aws.github.io/eks-charts"
  chart            = "aws-cloudwatch-metrics"
  namespace        = "amazon-cloudwatch"
  create_namespace = true

  set {
    name  = "hostNetwork"
    value = "true"
  }

  set {
    name  = "clusterName"
    value = aws_eks_cluster.main.name
  }

  depends_on = [aws_eks_cluster.main]
}