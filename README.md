# Cloud-Native Flask — Multi-Cloud Kubernetes Deployment

A production-style Flask application deployed independently on Azure (AKS) and AWS (EKS), with infrastructure, delivery, and observability fully defined as code.
## Pipeline Status

| | Azure | AWS |
|---|---|---|
| **Infra** | [![Terraform Infra Pipeline](https://github.com/nouraldeen417/cloud-native-flask/actions/workflows/infra-azure-deploy.yml/badge.svg)](https://github.com/nouraldeen417/cloud-native-flask/actions/workflows/infra-azure-deploy.yml) | [![Terraform Infra Pipeline (AWS)](https://github.com/nouraldeen417/cloud-native-flask/actions/workflows/infra-aws-deploy.yml/badge.svg)](https://github.com/nouraldeen417/cloud-native-flask/actions/workflows/infra-aws-deploy.yml) |
| **Build & Deploy** | [![Build and Push Flask App to ACR](https://github.com/nouraldeen417/cloud-native-flask/actions/workflows/azure-ci.yml/badge.svg)](https://github.com/nouraldeen417/cloud-native-flask/actions/workflows/azure-ci.yml) | [![Build Docker Image Workflow (AWS)](https://github.com/nouraldeen417/cloud-native-flask/actions/workflows/aws-ci.yml/badge.svg)](https://github.com/nouraldeen417/cloud-native-flask/actions/workflows/aws-ci.yml) |
| **Destroy** | [![Terraform Infra Destroy](https://github.com/nouraldeen417/cloud-native-flask/actions/workflows/infra-azure-destroy.yml/badge.svg)](https://github.com/nouraldeen417/cloud-native-flask/actions/workflows/infra-azure-destroy.yml) | [![Terraform Infra Destroy (AWS)](https://github.com/nouraldeen417/cloud-native-flask/actions/workflows/infra-aws-destroy.yml/badge.svg)](https://github.com/nouraldeen417/cloud-native-flask/actions/workflows/infra-aws-destroy.yml) |
---


## Table of Contents

- [Overview](#overview)
- [Architecture](#architecture)
- [Azure vs. AWS — Design Comparison](#azure-vs-aws--design-comparison)
- [Repository Structure](#repository-structure)
- [Documentation Index](#documentation-index)
- [CI/CD Pipelines](#cicd-pipelines)
- [Cross-Cloud Disaster Recovery](#cross-cloud-disaster-recovery)
- [Architecture Decisions & Tradeoffs](#architecture-decisions--tradeoffs)
- [Environment Notes](#environment-notes)
- [Project Gallery ](SCREENSHOTS.md)  

---

## Overview

**What's deployed, on both clouds:**
- Flask web app (user signup/login, wishlist CRUD) — `src/flaskapp`
- MySQL backing store (Azure MySQL Flexible Server / AWS RDS MySQL)
- Managed Kubernetes (AKS / EKS), provisioned entirely via Terraform
- Container registry (ACR / ECR), with Trivy vulnerability scanning gating every image push
- GitOps delivery via Argo CD — one instance per cluster, each watching its own Kustomize overlay
- Full observability: Azure Monitor + Log Analytics (KQL) on Azure; CloudWatch (Logs Insights + a fully Terraform-managed dashboard) on AWS
- **Cross-cloud disaster recovery**: nightly Azure→S3 backups via a security-first presigned-URL pattern, with a documented, tested restore path into AWS RDS
---
<div align="center" >
<img src="images/Multi-Cloud Flask architecture diagram.png" width="80%" alt="Image 2"/>
</div >


## Architecture

**Shared application layer**, one Kustomize `base/`:
```
Flask Deployment + Service + Ingress + DB schema (idempotent, Argo PreSync hook)
```
<div width="100%">
  <table>
    <tr>
          <td align="right"><img src="images/azure deployment.png" width="550" alt="Image 2"/></td>
          <td align="left"><img src="images/aws deployemnt.png" width="550" alt="Image 1"/></td>
    </tr>
    <tr>
      <td align="center"><b>Azure Architecture</b></td>
      <td align="center"><b>AWS Architecture </b></td>
    </tr>
  </table>
</div>
**Per-cloud overlay** — only what's genuinely cloud-specific:

| | Azure overlay | AWS overlay |
|---|---|---|
| Image registry | ACR | ECR |
| DB host | Azure MySQL FQDN (patched via Kustomize) | RDS endpoint (patched via Kustomize) |
| Secret delivery | Key Vault CSI (live sync) | Secrets Manager |

[See full comparison below](#azure-vs-aws--design-comparison) for how each cloud's secret store is wired to the cluster.

---

## Azure vs. AWS — Design Comparison

> This project's AWS environment is AWS Academy Learner Lab, which restricts IAM to pre-provisioned roles and issues short-lived session credentials. A few choices below follow from that constraint.

| Aspect | Azure | AWS |
|---|---|---|
| Secret delivery to pods | Key Vault CSI, live sync | Secrets Manager |
| Cluster/node roles | Custom Service Principals, RG-scoped | Pre-provisioned `LabRole` / `LabEksClusterRole` |
| State locking | Native Blob lease | Native S3 `use_lockfile` (TF ≥1.11) |
| Log/metric shipping | Built-in AKS addon | Two Helm charts (CSI driver + CloudWatch agent/Fluent Bit) |
| Dashboard-as-code | Manual (Portal) | Fully Terraform-managed |
| Ingress → Load Balancer | ingress-nginx + Azure DNS label | ingress-nginx + AWS NLB annotation |
| DB network exposure | Broad Azure-internal firewall rule | Security group scoped to EKS cluster only |

**Notes on a few of these:**
- **Secret delivery** — Azure's Key Vault CSI driver syncs live into the cluster; AWS's secret is provisioned into the cluster via Terraform rather than a live CSI sync.
- **Log/metric shipping** — genuine platform difference: AKS bundles this as a first-party addon; EKS has no native equivalent, so it's installed as two separate Helm charts.
- **Dashboard-as-code** — CloudWatch's dashboard JSON schema is materially more concise than Azure's ARM-template-style equivalent; Azure's closer match (`azurerm_application_insights_workbook`) wasn't adopted for this project.
- **Ingress → Load Balancer** — same controller on both, deliberately, for consistency between the two overlays.
- **DB network exposure** — AWS's security-group model allowed tighter scoping here than Azure's IP-range firewall model.

A cross-cloud issue surfaced and resolved during DR restore testing is documented in [`docs/Disaster-Recovery.md`](docs/Disaster-Recovery.md).

## Repository Structure

```
.
├── terraform/
│   ├── azure/           # RG (data source), VNet/Subnet, AKS, ACR, MySQL, Key Vault, RBAC, Argo CD + ingress-nginx (Helm), ACA DR backup job
│   └── aws/              # VPC/NAT, EKS + node group, ECR, RDS, Secrets Manager, CloudWatch (dashboard + agents), Argo CD + ingress-nginx (Helm)
├── kubernetes/
│   ├── base/              # Deployment, Service, Ingress, DB schema ConfigMap + PreSync Job — shared by both clouds
│   └── overlays/
│       ├── azure/         # image ref, DB host patch, StorageClass
│       └── aws/           # image ref, DB host patch, StorageClass
├── src/flaskapp/          # application code
├── DB_backup/             # Lambda presigned-URL function + K8s restore Job (DR)
├── argocd/                # Argo CD Application manifests, one per cloud
├── secret-key-vault-azure.yml   # applied manually — kept out of Argo's sync scope, see Architecture Decisions
├── secret-key-vault-aws.yml     # not used at runtime — AWS uses a Terraform-provisioned Secret instead; kept for reference
├── .github/workflows/     # 6 pipelines — infra + CI + destroy, ×2 clouds
├── docs/
│   ├── azure/              # PREREQUISITES.md, OPERATIONS.md, MONITORING.md
│   ├── aws/                # PREREQUISITES.md, OPERATIONS.md, MONITORING.md
│   └── DR.md                # cross-cloud disaster recovery — design, security model, procedure
├── images/                  # screenshots and diagrams used in this README
└── README.md
```

---

## Documentation Index

| Topic | Azure | AWS |
|---|---|---|
| One-time setup (identities, state backend, first apply) | [`docs/azure/PREREQUISITES.md`](docs/azure/PREREQUISITES.md) | [`docs/aws/PREREQUISITES.md`](docs/aws/PREREQUISITES.md) |
| Day-to-day operational commands | [`docs/azure/OPERATIONS.md`](docs/azure/OPERATIONS.md) | [`docs/aws/OPERATIONS.md`](docs/aws/OPERATIONS.md) |
| Observability setup (dashboards, queries, alerts) | [`docs/azure/MONITORING.md`](docs/azure/MONITORING.md) | [`docs/aws/MONITORING.md`](docs/aws/MONITORING.md) |

**Cross-cloud:** [`docs/Disaster-Recovery.md`](docs/Disaster-Recovery.md) — disaster recovery design, security model, and fail-over procedure.

---

## CI/CD Pipelines

Six pipelines total — infra, app build, and destroy, independently for each cloud:

| Pipeline | Trigger | Purpose |
|---|---|---|
| `infra-azure-deploy`  | push to `terraform/azure/**`, manual approval gate on apply | Terraform plan/apply, syncs `ACR_LOGIN_SERVER` + DB host to repo variables |
| `infra-aws-deploy.yml` | push to `terraform/aws/**`, manual approval gate on apply | Same, for AWS — syncs `ECR_REPOSITORY_URL` + RDS endpoint |
| `azure-ci.yml`  | push to `src/**`, or after successful Azure infra apply | Build → Trivy scan (gates on CRITICAL/HIGH) → push to ACR → patch Azure Kustomize overlay |
| `aws-ci.yml` | push to `src/**`, or after successful AWS infra apply | Same, for AWS — push to ECR → patch AWS Kustomize overlay |
| `infra-azure-destroy.yml` | manual only, typed confirmation + approval gate | Tears down Azure infra |
| `infra-aws-destroy.yml` | manual only, typed confirmation + approval gate | Tears down AWS infra |

Both `ci*.yml` pipelines use `kustomize edit set image`, not `sed`, to patch their respective overlay — each cloud's CI only ever touches its own overlay file, never the shared `base/` or the other cloud's overlay.

---

## Cross-Cloud Disaster Recovery

Nightly, Azure MySQL is backed up to a private, versioned S3 bucket — using a **presigned-URL pattern specifically so Azure never holds an AWS credential**. Restore into RDS runs as a Kubernetes Job entirely inside the EKS cluster's VPC — no public database access, no public bucket access, at any point in the flow.

Full design, security rationale, prerequisites, and the exact restore procedure (including a real collation-mismatch bug found and fixed during testing): **[`docs/Disaster-Recovery.md`](docs/Disaster-Recovery.md)**

---

## Architecture Decisions & Tradeoffs

Beyond the Azure-vs-AWS comparison table above:

- **PaaS over StatefulSet, both clouds** — managed MySQL instead of in-cluster database, avoiding Day 2 operational complexity.
- **Kustomize base + overlay, not duplicated manifests** — `base/` holds everything genuinely shared (Deployment, Service, Ingress, DB schema); overlays hold only real per-cloud differences (image reference, DB host, StorageClass). This was actively corrected once during the build after an early pass over-duplicated files that were 90% identical.
- **Single NAT Gateway (AWS), not per-AZ** — cost-conscious tradeoff for this project's scale; production would use per-AZ NAT for full HA.
- **RDS/MySQL parameter groups explicitly pin collation and enable slow/general/error logs** — server defaults aren't trustworthy across cloud providers, discovered directly via a real cross-cloud restore bug.
- **Trivy pinned to a commit SHA, not a version tag** — following the action maintainers' own post-incident supply-chain hardening guidance.
- **`SecretProviderClass` (Azure) applied manually, outside Argo's sync scope** — contains non-secret but still-not-public identifiers (vault name, tenant ID, identity client ID); kept out of the public repo as defense-in-depth beyond Azure's own sensitivity classification.

---

## Environment Notes

The AWS side of this project runs in **AWS Academy Learner Lab**, not a personal AWS account. Learner Lab imposes restricted IAM (no custom role/OIDC-provider creation beyond service-linked roles) and issues session-based, expiring credentials rather than persistent IAM users. Several architectural decisions in the comparison table above are direct, documented consequences of this constraint — not oversights. Full detail in [`docs/aws/PREREQUISITES.md`](docs/aws/PREREQUISITES.md).

## Screenshots 

To keep this documentation clean, all visual evidence—including the live application UI, complete monitoring dashboards, Argo CD sync states, and the step-by-step Disaster Recovery verification—has been compiled into a dedicated gallery.

📸 **[Click here to view the full Project Gallery (SCREENSHOTS.md)](SCREENSHOTS.md)**