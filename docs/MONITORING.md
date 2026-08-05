# Monitoring & Observability Setup

Step-by-step for setting up KQL queries, an alert rule, and a dashboard against the Log Analytics Workspace. This is a one-time, mostly portal-driven setup — see notes on why it isn't Terraform-automated at the bottom.

---

## Prerequisites

```bash
cd terraform
terraform output -raw log_analytics_workspace_id
```

Cluster should already be running with real traffic (or at least a few pod restarts / requests) so the queries return meaningful data — running these against a freshly-created, empty workspace will mostly show nothing.

---

## Step 1 — Open Log Analytics

Azure Portal → your Log Analytics Workspace → **Logs**

---

## Step 2 — Run and save each query

### Container / Ingress Queries

### Query 1: Failed container starts (last 24h)

```kql
KubePodInventory
| where TimeGenerated > ago(24h)
| where PodStatus == "Failed" or ContainerStatus == "CrashLoopBackOff" or ContainerStatus == "Error"
| summarize FailCount = count() by Name, ContainerStatus, bin(TimeGenerated, 1h)
| order by TimeGenerated desc
```

### Query 2: CPU usage per container (millicores, timechart)

```kql
Perf
| where TimeGenerated > ago(1h)
| where ObjectName == "K8SContainer"
| where CounterName == "cpuUsageNanoCores"
| extend CleanContainerName = extract(@"/([^/]+)$", 1, InstanceName)
// Divide by 1,000,000 to convert NanoCores to Millicores (mCPU)
| summarize AvgCPU_mCPU = avg(CounterValue) / 1000000 by CleanContainerName, bin(TimeGenerated, 5m)
| render timechart
```

### Query 3: Memory usage per container (MB, timechart)

```kql
Perf
| where TimeGenerated > ago(1h)
| where ObjectName == "K8SContainer"
| where CounterName == "memoryWorkingSetBytes"
| extend CleanContainerName = extract(@"/([^/]+)$", 1, InstanceName)
// Divide by 1024 twice to convert Bytes to Megabytes (MB)
| summarize AvgMemory_MB = avg(CounterValue) / 1024 / 1024 by CleanContainerName, bin(TimeGenerated, 5m)
| render timechart
```

### Query 4: Ingress success rate (2xx/3xx, timechart)

```kql
KubePodInventory
| where Name has "nginx"
| distinct ContainerID
| join kind=inner (
    ContainerLog
    | where TimeGenerated > ago(24h)
    // Extract any 200-399 status code (2xx means OK, 3xx means Redirect)
    | extend StatusCode = extract(@'"\s([23]\d{2})\s', 1, LogEntry)
    | where isnotempty(StatusCode)
) on ContainerID
// Group by the specific status code and plot it on a 15-minute timeline
| summarize SuccessCount = count() by StatusCode, bin(TimeGenerated, 15m)
| render timechart
```

### Query 5: Ingress error rate (4xx/5xx, timechart)

```kql
KubePodInventory
// 1. Find the pods with nginx in the name
| where Name has "nginx"
| distinct ContainerID
// 2. Join them to their actual text logs
| join kind=inner (
    ContainerLog
    | where TimeGenerated > ago(24h)
    // 3. Extract any 400-599 status code that appears right after the HTTP request string
    | extend StatusCode = extract(@'"\s([45]\d{2})\s', 1, LogEntry)
    // 4. Drop all the normal 200 OK traffic so we only chart the errors
    | where isnotempty(StatusCode)
) on ContainerID
// 5. Group by the specific error code and plot it on a 15-minute timeline
| summarize ErrorCount = count() by StatusCode, bin(TimeGenerated, 15m)
| render timechart
```

> If Query 4/5 come back empty, check the actual ingress-nginx log format first:
> ```bash
> kubectl logs -n ingress-nginx <controller-pod-name> --tail=20
> ```
> and adjust the regex to match the real status-code position in the log line — default nginx log format can vary slightly by chart version.

### Database Queries (Azure MySQL Flexible Server)

> These require diagnostic settings sending MySQL logs/metrics to this workspace (`MySqlAuditLogs`, `MySqlSlowLogs`, and platform metrics) — not enabled by the base Terraform config in this project. If these return no data, add an `azurerm_monitor_diagnostic_setting` targeting the MySQL Flexible Server resource, same pattern as the AKS control-plane diagnostic setting.

### Query 6: MySQL audit log — recent events

```kql
AzureDiagnostics
| where ResourceProvider == "MICROSOFT.DBFORMYSQL"
| where Category == "MySqlAuditLogs"
| project TimeGenerated, Resource,
    EventClass = column_ifexists("event_class_s", ""),
    EventSubclass = column_ifexists("event_subclass_s", ""),
    Database = column_ifexists("db_s", ""),
    QueryText = column_ifexists("sql_text_s", "")
| order by TimeGenerated desc
```

### Query 7: MySQL slow query log

```kql
AzureDiagnostics
| where ResourceProvider == "MICROSOFT.DBFORMYSQL"
| where Category == "MySqlSlowLogs"
| project TimeGenerated, Resource,
    QueryTime = column_ifexists("query_time_d", 0.0),
    Database = column_ifexists("db_s", ""),
    QueryText = column_ifexists("sql_text_s", "")
| order by TimeGenerated desc
```

### Query 8: MySQL server CPU (timechart)

```kql
AzureMetrics
| where ResourceProvider == "MICROSOFT.DBFORMYSQL"
| where MetricName == "cpu_percent"
| where TimeGenerated > ago(24h)
| summarize AvgCPU = avg(Average) by bin(TimeGenerated, 15m), Resource
| render timechart
```

**After each query runs successfully:** click **Save** (top toolbar) → give it a clear name (e.g. `failed-container-starts`, `container-cpu-usage`, `container-memory-usage`, `ingress-success-rate`, `ingress-error-rate`, `mysql-audit-log`, `mysql-slow-queries`, `mysql-cpu`) — this makes each reusable and pinnable in the next steps.

---

## Step 3 — Create an alert rule

Using the memory query (Query 3) as the trigger condition (adjust threshold to match your pod's `resources.limits.memory: 256Mi`):

**Via CLI:**
```bash
az monitor scheduled-query create \
  --name "high-pod-memory-alert" \
  --resource-group rg-flaskapp-dev \
  --scopes $(terraform output -raw log_analytics_workspace_id) \
  --condition "count 'Perf | where CounterName == \"memoryWorkingSetBytes\" | where CounterValue > 200000000' > 0" \
  --condition-query "Perf | where CounterName == \"memoryWorkingSetBytes\" | where CounterValue > 200000000" \
  --evaluation-frequency 5m \
  --window-size 5m \
  --severity 2
```

**Via Portal** (if the CLI syntax is finicky): Log Analytics Workspace → **Alerts** → **New alert rule** → select your saved memory query as the condition → set threshold (e.g. > 200MB) → set evaluation frequency (5 min) → **Create**.

**Note on cadence:** this alert genuinely runs on a schedule in the background (every 5 minutes here) — it's the one piece of this setup that's actually "live," unlike the dashboard tiles below.

---

## Step 4 — Build the dashboard

From each saved query's results view (Logs → open a saved query → run it):
1. Click **Pin to dashboard**
2. First time: create a new dashboard, name it e.g. `FlaskApp Monitoring`
3. Repeat for each saved query you want visible (container/ingress queries work immediately; DB queries need the diagnostic setting noted above first)
4. Arrange tiles as preferred in the dashboard editor — group container-level and DB-level tiles into separate rows for readability

**Dashboard refresh behavior:** tiles show a snapshot from whenever the dashboard was last opened/refreshed — not continuously live. Set an auto-refresh interval via the dropdown in the top-right of the dashboard view (5m/15m/1h) if you want it to update itself while left open.

---

## Step 5 — Verify end to end

```bash
kubectl get pods -n default   # trigger some real traffic/restarts if the queries are still empty
curl http://<ingress-dns-name>/
curl http://<ingress-dns-name>/nonexistent-route   # generates a 404, won't show in the 5xx query but confirms ingress logging works
```

Wait a few minutes for Container Insights' normal ingestion lag, then re-run the saved queries to confirm data is flowing.

---

## Why this isn't Terraform-automated

KQL queries, the dashboard, and (arguably) the alert rule are **demo/operational artifacts**, not infrastructure — they depend on the app already running and generating real signal, and iterating on a query's exact syntax is naturally a portal/interactive activity, not something that benefits from `terraform apply` cycles. Same category of decision as the SecretProviderClass and RG being handled outside full automation elsewhere in this project: automate what's repeatable infrastructure, do by hand what's a one-time interactive setup task.