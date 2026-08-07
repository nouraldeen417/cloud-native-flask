resource "helm_release" "ingress_nginx" {
  name             = "ingress-nginx"
  repository       = "https://kubernetes.github.io/ingress-nginx"
  chart            = "ingress-nginx"
  namespace        = "ingress-nginx"
  create_namespace = true
  version          = var.ingress_nginx_chart_version
  values = [
    <<-EOF
    controller:
      service:
        annotations:
          # Provisions an AWS Network Load Balancer (NLB)
          service.beta.kubernetes.io/aws-load-balancer-type: "nlb"
          # Ensures the Load Balancer is publicly accessible
          service.beta.kubernetes.io/aws-load-balancer-scheme: "internet-facing"
    EOF
  ]

  # Assuming your EKS cluster resource is named aws_eks_cluster.eks
  depends_on = [aws_eks_cluster.main]
}



