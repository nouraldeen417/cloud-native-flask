resource "aws_cloudwatch_dashboard" "flaskapp" {
  dashboard_name = "FlaskApp-Monitoring"

  dashboard_body = jsonencode({
    widgets = [
      # --- Row 1: Cluster Health ---
      {
        type   = "metric"
        x      = 0
        y      = 0
        width  = 8
        height = 6
        properties = {
          title   = "Cluster Node Count"
          region  = var.aws_region
          view    = "timeSeries"
          stacked = false
          metrics = [
            ["ContainerInsights", "cluster_node_count", "ClusterName", aws_eks_cluster.main.name, { stat = "Average" }],
            ["ContainerInsights", "cluster_failed_node_count", "ClusterName", aws_eks_cluster.main.name, { stat = "Average" }]
          ]
          period = 300
        }
      },
      {
        type   = "metric"
        x      = 8
        y      = 0
        width  = 8
        height = 6
        properties = {
          title   = "Cluster CPU / Memory Utilization"
          region  = var.aws_region
          view    = "timeSeries"
          stacked = false
          metrics = [
            ["ContainerInsights", "node_cpu_utilization", "ClusterName", aws_eks_cluster.main.name, { stat = "Average" }],
            ["ContainerInsights", "node_memory_utilization", "ClusterName", aws_eks_cluster.main.name, { stat = "Average" }]
          ]
          period = 300
        }
      },
      {
        type   = "metric"
        x      = 16
        y      = 0
        width  = 8
        height = 6
        properties = {
          title   = "Node Filesystem Utilization"
          region  = var.aws_region
          view    = "timeSeries"
          stacked = false
          metrics = [
            ["ContainerInsights", "node_filesystem_utilization", "ClusterName", aws_eks_cluster.main.name, { stat = "Average" }]
          ]
          period = 300
        }
      },

      # --- Row 2: Namespace-level resource usage ---
      {
        type   = "metric"
        x      = 0
        y      = 6
        width  = 12
        height = 6
        properties = {
          title   = "Pods Running per Namespace"
          region  = var.aws_region
          view    = "timeSeries"
          stacked = true
          metrics = [
            ["ContainerInsights", "namespace_number_of_running_pods", "ClusterName", aws_eks_cluster.main.name, "Namespace", "default", { stat = "Average", label = "default" }],
            ["ContainerInsights", "namespace_number_of_running_pods", "ClusterName", aws_eks_cluster.main.name, "Namespace", "ingress-nginx", { stat = "Average", label = "ingress-nginx" }],
            ["ContainerInsights", "namespace_number_of_running_pods", "ClusterName", aws_eks_cluster.main.name, "Namespace", "argocd", { stat = "Average", label = "argocd" }],
            ["ContainerInsights", "namespace_number_of_running_pods", "ClusterName", aws_eks_cluster.main.name, "Namespace", "amazon-cloudwatch", { stat = "Average", label = "amazon-cloudwatch" }]
          ]
          period = 300
        }
      },
      {
        type   = "metric"
        x      = 12
        y      = 6
        width  = 12
        height = 6
        properties = {
          title   = "Pod Restarts (default namespace)"
          region  = var.aws_region
          view    = "timeSeries"
          stacked = false
          metrics = [
            ["ContainerInsights", "pod_number_of_container_restarts", "ClusterName", aws_eks_cluster.main.name, "Namespace", "default", { stat = "Sum" }]
          ]
          period = 300
        }
      },

      # --- Row 3: Flask app pod resource usage ---
      {
        type   = "metric"
        x      = 0
        y      = 12
        width  = 12
        height = 6
        properties = {
          title   = "Flask Pod CPU / Memory Utilization"
          region  = var.aws_region
          view    = "timeSeries"
          stacked = false
          metrics = [
            ["ContainerInsights", "pod_cpu_utilization", "ClusterName", aws_eks_cluster.main.name, "Namespace", "default", { stat = "Average" }],
            ["ContainerInsights", "pod_memory_utilization", "ClusterName", aws_eks_cluster.main.name, "Namespace", "default", { stat = "Average" }]
          ]
          period = 300
        }
      },
      {
        type   = "metric"
        x      = 12
        y      = 12
        width  = 12
        height = 6
        properties = {
          title   = "Flask Pod Network I/O"
          region  = var.aws_region
          view    = "timeSeries"
          stacked = false
          metrics = [
            ["ContainerInsights", "pod_network_rx_bytes", "ClusterName", aws_eks_cluster.main.name, "Namespace", "default", { stat = "Average" }],
            ["ContainerInsights", "pod_network_tx_bytes", "ClusterName", aws_eks_cluster.main.name, "Namespace", "default", { stat = "Average" }]
          ]
          period = 300
        }
      },

      # --- Row 4: Ingress traffic, as charts (bar) instead of tables ---
      {
        type   = "log"
        x      = 0
        y      = 18
        width  = 12
        height = 6
        properties = {
          title  = "Ingress Error Rate (4xx/5xx)"
          region = var.aws_region
          view   = "bar"
          query  = <<-QUERY
            SOURCE '/aws/containerinsights/eks-${var.project_name}-${var.environment}/application'
            | fields @timestamp, log
            | filter kubernetes.container_name = "controller"
            | parse log /"\s(?<status_code>[45]\d{2})\s/
            | filter ispresent(status_code)
            | stats count() as ErrorCount by status_code, bin(15m)
          QUERY
        }
      },
      {
        type   = "log"
        x      = 12
        y      = 18
        width  = 12
        height = 6
        properties = {
          title  = "Ingress Success Rate (2xx/3xx)"
          region = var.aws_region
          view   = "bar"
          query  = <<-QUERY
            SOURCE '/aws/containerinsights/eks-${var.project_name}-${var.environment}/application'
            | fields @timestamp, log
            | filter kubernetes.container_name = "controller"
            | parse log /"\s(?<status_code>[23]\d{2})\s/
            | filter ispresent(status_code)
            | stats count() as SuccessCount by status_code, bin(15m)
          QUERY
        }
      },

      # --- Row 5: Failed starts / errors — stays a table, raw text can't chart ---
      {
        type   = "log"
        x      = 0
        y      = 24
        width  = 24
        height = 6
        properties = {
          title  = "Failed Container Starts / Errors (24h)"
          region = var.aws_region
          view   = "table"
          query  = <<-QUERY
            SOURCE '/aws/containerinsights/eks-${var.project_name}-${var.environment}/application'
            | fields @timestamp, kubernetes.pod_name, log
            | filter log like /(?i)(error|crashloopbackoff|failed)/
            | sort @timestamp desc
            | limit 50
          QUERY
        }
      },

      # --- Row 6: RDS ---
      {
        type   = "metric"
        x      = 0
        y      = 30
        width  = 8
        height = 6
        properties = {
          title   = "RDS CPU Utilization"
          region  = var.aws_region
          view    = "timeSeries"
          stacked = false
          metrics = [
            ["AWS/RDS", "CPUUtilization", "DBInstanceIdentifier", aws_db_instance.mysql.identifier, { stat = "Average" }]
          ]
          period = 300
        }
      },
      {
        type   = "metric"
        x      = 8
        y      = 30
        width  = 8
        height = 6
        properties = {
          title   = "RDS Freeable Memory"
          region  = var.aws_region
          view    = "timeSeries"
          stacked = false
          metrics = [
            ["AWS/RDS", "FreeableMemory", "DBInstanceIdentifier", aws_db_instance.mysql.identifier, { stat = "Average" }]
          ]
          period = 300
        }
      },
      {
        type   = "metric"
        x      = 16
        y      = 30
        width  = 8
        height = 6
        properties = {
          title   = "RDS Active Connections"
          region  = var.aws_region
          view    = "timeSeries"
          stacked = false
          metrics = [
            ["AWS/RDS", "DatabaseConnections", "DBInstanceIdentifier", aws_db_instance.mysql.identifier, { stat = "Average" }]
          ]
          period = 300
        }
      }
    ]
  })
}
