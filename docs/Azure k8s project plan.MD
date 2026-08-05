# Azure Cloud-Native Kubernetes Project — Implementation Plan

## Phase 0: Prerequisites (Do This First, Before Any `terraform apply`)

This phase has two parts: **Identity** (so GitHub Actions can talk to Azure) and **State & Locking** (so your Terraform doesn't corrupt itself). Both must exist before you write your first resource block.

### 0.1 Identity Setup (OIDC for GitHub Actions)

1. **Create the App Registration + Service Principal**
   ```bash
   az ad app create --display-name "flaskapp-github-oidc"
   az ad sp create --id <appId>
   ```
2. **Assign the role** — scope tightly to the ACR, not the whole subscription:
   ```bash
   az role assignment create \
     --assignee <appId> \
     --role AcrPush \
     --scope /subscriptions/<sub-id>/resourceGroups/<rg>/providers/Microsoft.ContainerRegistry/registries/<acr-name>
   ```
   (If ACR doesn't exist yet, use `Contributor` on the Resource Group temporarily, then re-scope to `AcrPush` on the ACR once it's created in Phase 1.)
3. **Create the Federated Credential** — decide your trigger strategy now:
   - Only push to `main` → subject: `repo:your-org/your-repo:ref:refs/heads/main`
   - Also want PR builds → add a **second** federated credential with subject: `repo:your-org/your-repo:pull_request`
   ```bash
   az ad app federated-credential create --id <appId> --parameters credential.json
   ```
4. **Add GitHub repo secrets**: `AZURE_CLIENT_ID`, `AZURE_TENANT_ID`, `AZURE_SUBSCRIPTION_ID`

### 0.2 Terraform State & Locking (Backend Setup)

Even for a local-run project, set up a remote backend — it protects you from corrupting state if you `Ctrl+C` mid-apply, and it's a two-minute setup that reads well in your README.

1. **Create a dedicated storage account for state** (separate from your app resources, created manually via CLI — not by the same Terraform it will later manage):
   ```bash
   az group create --name rg-tfstate --location <region>
   az storage account create --name sttfstate<uniqueid> --resource-group rg-tfstate --sku Standard_LRS
   az storage container create --name tfstate --account-name sttfstate<uniqueid>
   ```
2. **Configure the backend block** in your Terraform project:
   ```hcl
   terraform {
     backend "azurerm" {
       resource_group_name  = "rg-tfstate"
       storage_account_name = "sttfstate<uniqueid>"
       container_name        = "tfstate"
       key                   = "flaskapp.tfstate"
     }
   }
   ```
3. **Locking**: Azure Blob backend handles state locking natively via blob leases — no extra config needed. Just don't switch to local state later or you lose it.
4. **README line to add**: *"Terraform state is stored remotely in Azure Blob Storage with native lease-based locking, preventing concurrent apply conflicts — a minimum viable version of the state management a production Infra CI/CD pipeline would enforce."*

**Checkpoint before moving on:** you should now have GitHub secrets configured, a federated credential trusting your repo/branch, and an empty remote state container ready to receive your first `terraform init`.

---

## Phase 1: Terraform Build — Infrastructure (The Big Phase)

Build in this order because of dependencies — each resource below needs the one above it to exist first.

1. **Resource Group** — everything else scopes to this.
2. **Log Analytics Workspace** — must exist before AKS so you can wire up Container Insights at creation time, not bolt it on after.
3. **ACR (Azure Container Registry)** — needs to exist before AKS so you can grant the Kubelet Identity pull access at cluster creation.
4. **AKS Cluster**
   - `oms_agent` block → link to the Log Analytics Workspace (Container Insights).
   - `acr_role_based_access_control` / attach via `az aks update --attach-acr` equivalent in Terraform → grants Kubelet Identity `AcrPull` on your registry automatically (no manual secret needed).
5. **Azure Database for MySQL Flexible Server** — **decide networking mode now**:
   - **Public access + firewall rule** (simpler, recommended for your 10-day window): allow AKS's outbound IP(s), or `0.0.0.0`–`255.255.255.255` scoped down later if time allows.
   - **Private endpoint into AKS's VNet** (more "correct," more Terraform): only pick this if you have slack in your timeline — it adds VNet peering/subnet delegation complexity.
   - Either way, note the choice explicitly in your README as a conscious tradeoff.
6. **Terraform Helm Provider — bootstrap cluster tooling** (runs after AKS is up):
   - `helm_release "argocd"` — your CD engine.
   - `helm_release "ingress-nginx"` — **this was missing from the original plan.** The Ingress *resource* you write in Phase 2 does nothing without this controller deployed. Add it here, same pattern as Argo CD.

**Resource connection map** (how they wire together):
```
Log Analytics Workspace ──▶ AKS (Container Insights)
ACR ──▶ AKS (Kubelet Identity pull access)
AKS ──▶ Helm Provider ──▶ Argo CD + ingress-nginx (installed as workloads on the cluster)
MySQL Flexible Server ──▶ reachable from AKS via firewall rule OR private endpoint
```

**Apply:**
```bash
terraform init
terraform plan -out=tfplan
terraform apply tfplan
```

---

## Phase 2: Application CI Pipeline (GitHub Actions)

`.github/workflows/docker-build.yml`:
- Checkout code
- `azure/login` with OIDC (`client-id`, `tenant-id`, `subscription-id` from secrets)
- Login to ACR
- Build `flaskapp` image
- Push to ACR

---

## Phase 3: Kubernetes Manifests

- **Namespaces**: separate `argocd`, `ingress-nginx`, and your app namespace from the start — don't run flat.
- **Secret** for DB password; **ConfigMap** for DB user/host/name (host = your MySQL Flexible Server FQDN).
- **StorageClass** (Azure Files CSI) + **PVC**.
- **Deployment**: ACR image, mount ConfigMap/Secret as env vars, mount PVC to `/app/uploads` or similar, readiness/liveness/startup probes, resource limits.
- **Service** (ClusterIP) + **Ingress** (now has a controller to talk to, from Phase 1).
- **NetworkPolicy** — be explicit, don't leave it vague:
  - Allow ingress only from the `ingress-nginx` namespace.
  - Allow egress only to the MySQL endpoint (port 3306) + DNS (port 53).
  - Deny all other traffic by default.

**Optional stretch goal for the README**: mention the Azure Key Vault CSI driver as the natural next step beyond a plain K8s Secret — you don't have to implement it, but naming the gap shows you know it.

---

## Phase 4: Continuous Delivery (Argo CD)

- Access the Argo CD UI (already deployed via Terraform in Phase 1).
- Connect it to the GitHub repo holding your K8s manifests.
- Configure auto-sync.

---

## Phase 5: Observability (Azure Monitor & KQL)

- Write KQL queries: failed container starts, high CPU/memory, ingress error rates.
- Create an Azure Alert Rule off one query.
- Pin results to a custom Azure Dashboard.

---

## Phase 6: Validation, Recording, Teardown

- Record: `kubectl get all -A`, working browser URL, Argo CD dashboard, Azure Monitor dashboard.
- **Cost control while working**: `az aks stop` overnight instead of destroying/reapplying; use `Standard_B2s` nodes and `B_Standard_B1ms` MySQL tier.
- **Teardown**: `terraform destroy` — note that your `rg-tfstate` resource group (Phase 0.2) is separate and won't be destroyed by this, which is intentional — keep your state backend alive across the project.

---

## README Talking Points (Consolidated)

- **PaaS vs StatefulSet**: managed MySQL over in-cluster database — Day 2 ops tradeoff.
- **Local Terraform, OIDC-scoped app pipeline**: explicit split between infra and app trust boundaries.
- **Remote state + native locking**: prevents concurrent-apply corruption, minimum viable version of a production state strategy.
- **Ansible vs Terraform Helm**: Helm provider is the efficient IaC path for AKS tooling bootstrap.
- **Azure Files for stateless app**: demonstrates CSI dynamic provisioning even though the app itself doesn't strictly need persistent storage.
- **MySQL networking choice**: state explicitly whether you used public+firewall or private endpoint, and why (time constraint).
- **NetworkPolicy**: default-deny posture with explicit allow rules, not just "a policy exists."
- **Key Vault CSI**: named as the production-grade next step beyond K8s Secrets.