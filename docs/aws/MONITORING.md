# Monitoring & Observability Setup (AWS)

Step-by-step for CloudWatch Logs Insights queries, an alarm, and a dashboard. Mirrors `docs/azure/MONITORING.md` in structure — same goals, different query language (CloudWatch Logs Insights instead of KQL) and different underlying log groups.

---

## What's already flowing in automatically (no manual step needed)

Unlike Azure, where diagnostic settings had to be added as a separate Terraform resource, most AWS log shipping is already configured directly on the resources themselves:

- **EKS control plane logs** — `enabled_cluster_log_types` on `aws_eks_cluster` ships to `/aws/eks/<cluster-name>/cluster`
- **RDS logs** — `enabled_cloudwatch_logs_exports` on `aws_db_instance` ships audit/error/general/slowquery logs to `/aws/rds/instance/<db-identifier>/<log-type>`
- **Pod/container logs + metrics** — the `aws-cloudwatch-metrics` Helm release (Container Insights agent) ships to `/aws/containerinsights/<cluster-name>/...` log groups

Confirm all three exist before writing queries:
```bash
aws logs describe-log-groups --query "logGroups[].logGroupName" --output table
```
You should see log groups matching all three patterns above. If any are missing, check the corresponding Terraform resource applied cleanly.

---

## Step 1 — Open CloudWatch Logs Insights

AWS Console → CloudWatch → **Logs Insights** → select the relevant log group from the dropdown before running each query below.

---

## Step 2 — Run and save each query

### Container / Pod Queries

Log group: `/aws/containerinsights/eks-flaskapp-dev/application`

### Query 1: Failed container starts / errors (last 24h)

```
fields @timestamp, kubernetes.pod_name, kubernetes.container_name, log
| filter log like /(?i)(error|crashloopbackoff|failed)/
| sort @timestamp desc
| limit 50
```

### Query 2: Ingress error rate (4xx/5xx)

```
fields @timestamp, log
| filter kubernetes.container_name like /nginx/
| parse log /"\s(?<status_code>[45]\d{2})\s/
| filter ispresent(status_code)
| stats count() as ErrorCount by status_code, bin(15m)
```

### Query 3: Ingress success rate (2xx/3xx)

```
fields @timestamp, log
| filter kubernetes.container_name like /nginx/
| parse log /"\s(?<status_code>[23]\d{2})\s/
| filter ispresent(status_code)
| stats count() as SuccessCount by status_code, bin(15m)
```

> If Queries 2/3 return nothing, check the actual ingress-nginx log format first:
> ```bash
> kubectl logs -n ingress-nginx <controller-pod-name> --tail=20
> ```
> and adjust the `parse` pattern to match where the status code actually sits in the line.

### CPU / Memory — use Metrics, not Logs Insights

Container Insights ships CPU/memory as **CloudWatch Metrics**, not as log lines — querying them via Logs Insights isn't the right tool here (unlike Azure, where `Perf` is itself a queryable log-like table). Use the Metrics console instead:

CloudWatch → **Metrics** → **Container Insights** → select `ContainerInsights` namespace → filter by `ClusterName` = `eks-flaskapp-dev` → pick `pod_cpu_utilization` / `pod_memory_utilization` → **Graphed metrics** tab → adjust statistic to `Average`, period to `5 minutes`.

Or via CLI, to confirm data exists before building graphs:
```bash
aws cloudwatch get-metric-statistics \
  --namespace ContainerInsights \
  --metric-name pod_memory_utilization \
  --dimensions Name=ClusterName,Value=eks-flaskapp-dev \
  --start-time $(date -u -d '1 hour ago' +%Y-%m-%dT%H:%M:%S) \
  --end-time $(date -u +%Y-%m-%dT%H:%M:%S) \
  --period 300 \
  --statistics Average
```

### Database Queries (RDS)

Log group: `/aws/rds/instance/rds-flaskapp-dev/slowquery` (and `/error`, `/general`, `/audit` — same pattern, different suffix)

### Query 4: RDS slow queries

```
fields @timestamp, @message
| filter @logStream like /slowquery/
| sort @timestamp desc
| limit 50
```

### Query 5: RDS errors

```
fields @timestamp, @message
| filter @logStream like /error/
| sort @timestamp desc
| limit 50
```

### RDS CPU — Metrics, not Logs Insights

```bash
aws cloudwatch get-metric-statistics \
  --namespace AWS/RDS \
  --metric-name CPUUtilization \
  --dimensions Name=DBInstanceIdentifier,Value=rds-flaskapp-dev \
  --start-time $(date -u -d '24 hours ago' +%Y-%m-%dT%H:%M:%S) \
  --end-time $(date -u +%Y-%m-%dT%H:%M:%S) \
  --period 900 \
  --statistics Average
```

**Save each Logs Insights query:** after running it, click **Save** (top toolbar) → give it a clear name (e.g. `failed-container-starts`, `ingress-error-rate`, `ingress-success-rate`, `rds-slow-queries`, `rds-errors`) — reusable and addable to a dashboard from here.

---

## Step 3 — Create a CloudWatch Alarm

Using pod memory utilization as the trigger condition (adjust threshold to match your pod's `resources.limits.memory: 256Mi`):

**Via CLI:**
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

**Via Console** (if CLI syntax is finicky): CloudWatch → **Alarms** → **Create alarm** → select metric `ContainerInsights → pod_memory_utilization` filtered to your cluster → set threshold (e.g. > 80%) → **Create alarm**.

**Note on cadence:** same as Azure's alert rule — this genuinely evaluates on a schedule (every `--period` seconds) in the background, independent of whether you have the console open.

---

## Step 4 — Build the dashboard

**Via Console:**
1. CloudWatch → **Dashboards** → **Create dashboard** → name it `FlaskApp-Monitoring`
2. Add widgets:
   - **Logs table** widget → source from each saved Logs Insights query (failed starts, ingress errors, RDS slow queries)
   - **Metric** widgets → `pod_cpu_utilization`, `pod_memory_utilization`, RDS `CPUUtilization`
3. Arrange — group container-level and RDS-level widgets into separate rows for readability, same convention as the Azure dashboard.

**Via CLI** (faster if you want it scripted/reproducible):
```bash
aws cloudwatch put-dashboard \
  --dashboard-name FlaskApp-Monitoring \
  --dashboard-body file://dashboard-body.json
```
Building `dashboard-body.json` by hand is fiddly — easiest path is to build the dashboard once in the console, then export it:
```bash
aws cloudwatch get-dashboard --dashboard-name FlaskApp-Monitoring --query DashboardBody --output text > dashboard-body.json
```
Keep this JSON in the repo if you want the dashboard itself version-controlled and reproducible on a fresh AWS account later — a nice parity point with your IaC-everything philosophy elsewhere, though not required.

**Dashboard refresh behavior:** same as Azure — snapshot on open/refresh, not continuously live. Set the auto-refresh interval via the dropdown in the top-right of the dashboard view.

---

## Step 5 — Verify end to end

```bash
kubectl get pods -n default
NLB_HOST=$(kubectl get svc -n ingress-nginx ingress-nginx-controller -o jsonpath="{.status.loadBalancer.ingress[0].hostname}")
curl http://$NLB_HOST/
curl http://$NLB_HOST/nonexistent-route   # generates a 404
```

Wait a few minutes for Container Insights' normal ingestion lag, then re-run the saved queries to confirm data is flowing.

---

## Why alarm/dashboard stay manual (same reasoning as Azure)

Log shipping itself is Terraform-managed (unlike Azure, where it needed an explicit diagnostic-setting resource — AWS's version lives directly on the resource config, arguably simpler). The alarm and dashboard remain portal/CLI-driven one-time setup, consistent with the Azure side: these are demo/operational artifacts that depend on the app already generating real signal, not infrastructure worth `terraform apply` cycles for a project at this scale.