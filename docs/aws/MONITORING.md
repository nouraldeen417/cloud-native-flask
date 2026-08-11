# Monitoring & Observability Setup (AWS)

Unlike the Azure setup (manual queries saved and pinned via Portal), the AWS dashboard is **fully Terraform-managed** — `terraform apply` creates the entire dashboard, all widgets, all queries, in one step. This section documents that as the primary setup path. Ad-hoc Logs Insights queries are covered afterward as a debugging reference, not as the way the dashboard gets built.

---

## What's already flowing in automatically (no manual step needed)

Same as before — log/metric shipping is configured directly on the Terraform-managed resources themselves, no separate diagnostic-setting step required:

- **EKS control plane logs** — `enabled_cluster_log_types` on `aws_eks_cluster` → `/aws/eks/<cluster-name>/cluster`
- **RDS logs** — `enabled_cloudwatch_logs_exports` on `aws_db_instance` → `/aws/rds/instance/<db-identifier>/<log-type>`
- **Pod/container metrics** — `aws-cloudwatch-metrics` Helm release (requires `hostNetwork: true` — see the known-issue note below)
- **Pod/container logs** — `aws-for-fluent-bit` Helm release (requires `hostNetwork: true` **and** `dnsPolicy: ClusterFirstWithHostNet` — see below)

Confirm all four exist:
```bash
aws logs describe-log-groups --query "logGroups[].logGroupName" --output table
kubectl get pods -n amazon-cloudwatch
```

### Known issue: both Helm-based collectors require `hostNetwork: true`

EKS-managed node groups default to an IMDS hop limit of 1, which blocks pod-level processes (2 hops away) from reaching instance metadata — both `aws-cloudwatch-metrics` and `aws-for-fluent-bit` need this to authenticate to AWS APIs. Fix applied in this project's `cloudwatch.tf`:
```hcl
set {
  name  = "hostNetwork"
  value = "true"
}
```
Fluent Bit additionally needs `dnsPolicy: ClusterFirstWithHostNet`, since `hostNetwork: true` alone switches DNS resolution to the node's resolver, breaking its in-cluster Kubernetes API lookup (`kubernetes.default.svc.cluster.local`) used for pod metadata enrichment. Both settings are already applied in this project's Terraform — documented here in case a chart upgrade resets them.

---

## Step 1 — Deploy the dashboard via Terraform

```bash
cd terraform/aws
terraform apply
terraform output -raw dashboard_url
```

Open the URL. You should see six rows: cluster health (node count/failures, CPU/memory, filesystem), namespace-level pod counts + restarts, Flask pod CPU/memory/network, ingress error/success rate (bar charts), failed container starts (table — raw text listings can't chart), and RDS (CPU, freeable memory, connections).

**If any metric widget is blank**, confirm the exact metric name is actually emitted by your agent version before assuming the widget is broken:
```bash
aws cloudwatch list-metrics --namespace ContainerInsights --query "Metrics[].MetricName" --output table | sort -u
```
Cross-check against `cloudwatch-dashboard.tf` — this project already hit one case where `cluster_cpu_utilization` didn't exist and had to be swapped for `node_cpu_utilization` (functionally equivalent, different name in this agent version).

**If the ingress bar charts are empty**, confirm real ingress-nginx log lines are present before assuming the parse regex is wrong:
```
fields @timestamp, log
| filter kubernetes.container_name = "controller"
| filter ispresent(log)
| sort @timestamp desc
| limit 10
```
Run against the `application` log group specifically (deselect other log groups in the picker) — mixing in `cluster`/`performance` log groups returns EKS audit events and EMF metric JSON that superficially match a loose `like /nginx/` filter but contain no real access-log content.

---

## Step 2 — Alarm

```bash
aws cloudwatch put-metric-alarm \
  --alarm-name "high-pod-memory-alert" \
  --namespace ContainerInsights \
  --metric-name pod_memory_utilization \
  --dimensions Name=ClusterName,Value=eks-flaskapp-dev \
  --statistic Average \
  --period 300 \
  --evaluation-periods 1 \
  --threshold 80 \
  --comparison-operator GreaterThanThreshold \
  --treat-missing-data notBreaching
```
Not yet moved into Terraform (`aws_cloudwatch_metric_alarm` is a straightforward addition if you want full parity later) — created via CLI for this project.

---

## Step 3 — Verify end to end

```bash
kubectl get pods -n default
NLB_HOST=$(kubectl get svc -n ingress-nginx ingress-nginx-controller -o jsonpath="{.status.loadBalancer.ingress[0].hostname}")
curl http://$NLB_HOST/
curl http://$NLB_HOST/nonexistent-route
```
Wait a few minutes for ingestion lag, then refresh the dashboard.

---

## Reference: ad-hoc Logs Insights queries (debugging, not setup)

Useful for investigating something the dashboard doesn't already surface — not required for the dashboard itself, which is fully described by `cloudwatch-dashboard.tf`.

### Query: raw ingress-nginx log lines, no aggregation
```
fields @timestamp, log
| filter kubernetes.container_name = "controller"
| filter ispresent(log)
| sort @timestamp desc
| limit 50
```

### Query: RDS slow queries
```
fields @timestamp, @message
| filter @logStream like /slowquery/
| sort @timestamp desc
| limit 50
```

### Query: RDS errors
```
fields @timestamp, @message
| filter @logStream like /error/
| sort @timestamp desc
| limit 50
```

---

## Why the dashboard is Terraform-managed here but manual on Azure

CloudWatch's dashboard resource (`aws_cloudwatch_dashboard`) has a concise, hand-writable JSON schema for widgets. Azure's equivalent (`azurerm_portal_dashboard`) requires verbose ARM-template-style part definitions; the closer functional match (`azurerm_application_insights_workbook`) wasn't adopted for the Azure side of this project. This is a genuine platform difference in dashboard-as-code maturity, not inconsistent effort — see the root README's Architecture Decisions section.