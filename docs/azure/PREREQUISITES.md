# Prerequisites — One-Time Manual Setup

These steps happen **once**, outside any pipeline, using your own `az login` (admin) identity. After this is done, the infra and app pipelines handle everything else automatically. Run commands in order — later steps depend on earlier ones.

---

## 0. Login and confirm your subscription

```bash
az login
az account show --query "{name:name, id:id}" -o table
```

---

## 1. Create the Resource Group

Terraform manages everything *inside* this RG but not the RG itself (see [README's Architecture Decisions section](../../README.md#architecture-decisions--tradeoffs) for why).

```bash
az group create --name rg-flaskapp-dev --location <region>
```

Use a region that supports both AKS and MySQL Flexible Server for your subscription tier — check availability first if unsure:

```bash
az aks get-versions --location <region> --output table
az mysql flexible-server list-skus --location <region> --output table
```

---

## 2. Create the two Service Principals (OIDC identities)

### 2a. App pipeline SP — builds/pushes images only

```bash
az ad app create --display-name "flaskapp-github-oidc"
az ad sp create --id <app-client-id-from-above>
```

Role assignment happens **after** the ACR exists (Step 8 below) — this SP has no permissions yet.

### 2b. Infra pipeline SP — runs Terraform

```bash
az ad app create --display-name "terraform-infra-github-oidc"
az ad sp create --id <infra-client-id-from-above>
```

Grant `Owner`, scoped to the RG only (not the subscription):

```bash
RG_ID=$(az group show --name rg-flaskapp-dev --query id -o tsv)

az role assignment create \
  --assignee <infra-client-id> \
  --role Owner \
  --scope "$RG_ID"
```

---

## 3. Create federated (OIDC) credentials for both SPs

GitHub embeds immutable numeric IDs in the subject claim if your username or repo has ever been renamed. Get the exact subject GitHub will send before creating these — easiest way is to attempt a pipeline run once and read the exact string from the `AADSTS700213` error if it fails, or construct it directly:

```
repo:<owner>[@<immutable-id>]/<repo>[@<immutable-id>]:ref:refs/heads/main
```

**App pipeline SP:**
```bash
cat > credential-app.json << 'EOF'
{
  "name": "github-actions-main",
  "issuer": "https://token.actions.githubusercontent.com",
  "subject": "repo:<owner>/<repo>:ref:refs/heads/main",
  "audiences": ["api://AzureADTokenExchange"]
}
EOF

az ad app federated-credential create \
  --id <app-client-id> \
  --parameters credential-app.json
```

**Infra pipeline SP:**
```bash
cat > credential-infra.json << 'EOF'
{
  "name": "github-actions-main",
  "issuer": "https://token.actions.githubusercontent.com",
  "subject": "repo:<owner>/<repo>:ref:refs/heads/main",
  "audiences": ["api://AzureADTokenExchange"]
}
EOF

az ad app federated-credential create \
  --id <infra-client-id> \
  --parameters credential-infra.json
```

Verify:
```bash
az ad app federated-credential list --id <app-client-id>
az ad app federated-credential list --id <infra-client-id>
```

### 3a. If you hit `AADSTS700213` (username/repo rename) or need environment-scoped jobs

Two situations that the simple exact-subject credential above doesn't cover:

**Problem 1 — GitHub embeds immutable IDs if your username/repo was ever renamed**, making the subject unpredictable ahead of time. Fix: use a **wildcard claims matching expression** instead of an exact `subject`. This is a preview feature not yet supported by `az ad app federated-credential create` — it must be created via `az rest` against Microsoft Graph directly, or via the Azure Portal.

**Via CLI (`az rest`):**
```bash
OBJECT_ID=$(az ad app show --id <app-client-id> --query id -o tsv)

az rest --method post \
  --url "https://graph.microsoft.com/beta/applications/${OBJECT_ID}/federatedIdentityCredentials" \
  --body "{'name': 'github-actions-main', 'issuer': 'https://token.actions.githubusercontent.com', 'audiences': ['api://AzureADTokenExchange'], 'claimsMatchingExpression': {'value': \"claims['sub'] matches 'repo:<owner>*/<repo>*:ref:refs/heads/main'\", 'languageVersion': 1}}"
```

**Via Portal (equivalent, used in this project):**
Entra ID → App registrations → your app → Certificates & secrets → Federated credentials → Add credential → scenario **"Other issuer"** → paste the claims matching expression as the Value:
```
claims['sub'] matches 'repo:<owner>*/<repo>*:ref:refs/heads/main'
```

> Wildcards match on **names**, which can be reclaimed if abandoned — Microsoft's own guidance recommends ID-based claims for broad wildcards in higher-security contexts. Acceptable tradeoff here given the project's scope; not something to default to blindly in production.

**Problem 2 — jobs using `environment:` (the manual-approval gate) send a different `sub` claim** than plain branch-triggered jobs: `repo:<owner>/<repo>:environment:<environment-name>` instead of `repo:<owner>/<repo>:ref:refs/heads/main`. Any job with `environment: production` in its YAML (this project's `apply` and `destroy` jobs) needs its own credential — exact subject works fine here, no wildcard needed:

```bash
cat > credential-environment.json << 'EOF'
{
  "name": "github-actions-environment",
  "issuer": "https://token.actions.githubusercontent.com",
  "subject": "repo:<owner>/<repo>:environment:production",
  "audiences": ["api://AzureADTokenExchange"]
}
EOF

az ad app federated-credential create \
  --id <infra-client-id> \
  --parameters credential-environment.json
```

> Only needed on the **infra pipeline SP** in this project, since only its `apply`/`destroy` jobs use `environment: production`. The app pipeline SP's jobs don't use an environment gate, so it only needs the wildcard/branch credential.

---

## 4. Create the Terraform remote state backend

Separate storage account, created manually (not by the Terraform it will later manage state for).

```bash
az group create --name rg-tfstate --location <region>
az storage account create --name sttfstate<uniqueid> --resource-group rg-tfstate --sku Standard_LRS
az storage container create --name tfstate --account-name sttfstate<uniqueid>
```

Reference these values in `terraform/backend.tf`.

---

## 5. Populate GitHub secrets and variables

Run the fetch-and-sync script (`sync-azure-ids-to-github.sh`) or do it manually:

```bash
SUBSCRIPTION_ID=$(az account show --query id -o tsv)
TENANT_ID=$(az account show --query tenantId -o tsv)
APP_CLIENT_ID=$(az ad app list --display-name "flaskapp-github-oidc" --query "[0].appId" -o tsv)
INFRA_CLIENT_ID=$(az ad app list --display-name "terraform-infra-github-oidc" --query "[0].appId" -o tsv)

gh secret set AZURE_SUBSCRIPTION_ID --body "$SUBSCRIPTION_ID"
gh secret set AZURE_TENANT_ID --body "$TENANT_ID"
gh secret set AZURE_CLIENT_ID --body "$APP_CLIENT_ID"
gh secret set AZURE_INFRA_CLIENT_ID --body "$INFRA_CLIENT_ID"
gh secret set MYSQL_ADMIN_PASSWORD --body "<your DB password>"
```

**Fine-grained PAT** (needed only for the `ACR_LOGIN_SERVER` auto-sync step in the infra pipeline, since the default `GITHUB_TOKEN` cannot manage repo Variables):

1. GitHub → Settings → Developer settings → Personal access tokens → Fine-grained tokens → Generate new
2. Repository access: this repo only
3. Permissions → Repository → Variables: Read and write
4. Store it:
```bash
gh secret set ADMIN_PAT
```

Also required: repo Settings → Actions → General → Workflow permissions → **Read and write permissions** (needed for the `apply` job's `actions: write` permission to actually take effect — repo-level setting is a hard ceiling on what job-level `permissions:` can request).

---

## 6. Import the Resource Group into Terraform state

```bash
cd terraform/azure
terraform init
terraform import azurerm_resource_group.rg /subscriptions/<sub-id>/resourceGroups/rg-flaskapp-dev
terraform plan   # should show 0 changes for the RG
```

> This repo's config references the RG as a `data` source, not a managed `resource` — so `terraform destroy` never touches it. The import above is only needed if you're using an earlier version of this config with a `resource` block.

---

## 7. First apply — two-stage, locally

The `helm` provider config depends on `azurerm_kubernetes_cluster.aks.kube_config`, which doesn't exist until AKS is created — so the very first apply must be split:

```bash
terraform apply -target=azurerm_kubernetes_cluster.aks
terraform apply
```

After this first run, subsequent applies (local or via the infra pipeline) work normally without targeting.

---

## 8. Grant AcrPush to the app pipeline SP

By this point ACR exists. This is already wired into `rbac.tf` via the `app_pipeline_sp_object_id` variable — set it once:

```bash
az ad sp show --id <app-client-id> --query id -o tsv
```
paste the result into `terraform.tfvars` as `app_pipeline_sp_object_id`, then the next `terraform apply` (local or CI) grants the role automatically.

---

## 9. Connect to the cluster and bootstrap Argo CD + secrets

```bash
az aks get-credentials --resource-group rg-flaskapp-dev --name aks-flaskapp-dev
kubectl apply -f argocd-app.yaml
kubectl apply -f secret-provider-class.yml   # kept out of the Argo-synced folder — see ../../README.md
```

From here, Argo CD takes over syncing everything in `kubernetes/`.

---

Full ongoing operational commands (day-to-day, not one-time setup) are in the project's command cheat sheet, not this file.