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
          service.beta.kubernetes.io/azure-dns-label-name: "${var.project_name}-${var.environment}"
    EOF
  ]
  depends_on = [azurerm_kubernetes_cluster.aks]
}