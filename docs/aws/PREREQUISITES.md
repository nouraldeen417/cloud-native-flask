# Prerequisites (AWS) — One-Time Manual Setup

## Environment note — read this first

This AWS environment is **AWS Academy Learner Lab**, not a personal AWS account. Learner Lab imposes two constraints that directly shaped several decisions documented here and across `docs/aws/`:

- **Restricted IAM** — no creating custom IAM users, groups, or roles (service-linked roles excepted). Pre-provisioned roles (`LabRole`, `LabEksClusterRole`) must be referenced as existing resources, not created.
- **Session-based, expiring credentials** — `AWS_ACCESS_KEY_ID` / `AWS_SECRET_ACCESS_KEY` / `AWS_SESSION_TOKEN` are issued per lab session and expire, unlike a permanent IAM user's keys. No GitHub OIDC federation is possible as a result (see the Azure implementation for what that pattern looks like where IAM allows it).

Where a design choice in this project differs from the Azure implementation, check the root `README.md`'s Architecture Decisions table first — it's very likely a direct, documented consequence of one of the two constraints above, not an oversight.

---

## 0. Get Learner Lab session credentials and confirm access

Start your Learner Lab session, open "AWS Details" → copy the credentials block, then:
```bash
./aws-creditional.sh
aws sts get-caller-identity
```
Confirms credentials are valid before doing anything else. **Re-run this script every time your Learner Lab session restarts** — credentials expire independent of any pipeline schedule.

---

## 1. Identify the pre-provisioned Learner Lab roles

```bash
aws iam list-roles --query "Roles[?contains(RoleName, 'Lab')].RoleName" -o table
```
Confirm `LabRole` and `LabEksClusterRole` (or equivalent EKS-specific role names per your lab guide) exist. These are referenced via Terraform `data` sources — never created — throughout `terraform/aws/`.

**Confirmed permissions relevant to this project** (from the Learner Lab guide):
- `LabRole` — read-only ECR; **write** access to ECR requires your personal console/session credentials, not `LabRole`
- `LabRole` — Secrets Manager access confirmed
- `LabEksClusterRole` — usable for both EKS cluster and node group roles
- IAM — cannot create roles/users/OIDC providers beyond service-linked roles

---

## 2. Create the Terraform remote state backend (S3, native locking)

```bash
aws s3api create-bucket --bucket flaskapp-tfstate-aws-<uniqueid> --region us-east-1
aws s3api put-bucket-versioning --bucket flaskapp-tfstate-aws-<uniqueid> --versioning-configuration Status=Enabled
```
No DynamoDB table needed — this project uses S3's native locking (`use_lockfile = true`, Terraform >= 1.11). Confirm your CLI version:
```bash
terraform version
```

Reference the bucket name in `terraform/aws/backend.tf`.

---

## 3. Populate GitHub secrets and variables

```bash
gh secret set AWS_ACCESS_KEY_ID       # from refresh-aws-lab-creds.sh / Learner Lab session
gh secret set AWS_SECRET_ACCESS_KEY
gh secret set AWS_SESSION_TOKEN
gh secret set AWS_MYSQL_ADMIN_PASSWORD
```

Reuse the same `ADMIN_PAT` and repo-level "Read and write permissions" setting already configured for the Azure side (`docs/azure/PREREQUISITES.md` section 5) — both are shared across the whole repo, not per-cloud.

**These first three secrets go stale on every Learner Lab session restart.** Re-run `./refresh-aws-lab-creds.sh` to update them — this is the single most common cause of pipeline failures on the AWS side.

---

## 4. First apply — three-stage, locally

AWS needs one more stage than Azure did, since three separate provider configs (`helm`, `kubernetes`, and the `aws_eks_cluster_auth` data source they both depend on) all need the EKS cluster to exist first:

```bash
cd terraform/aws
terraform init
terraform apply -target=aws_eks_cluster.main
terraform apply
```

If you still hit a provider configuration error on the second command, confirm `data "aws_eks_cluster_auth" "main"` is actually declared somewhere in the directory (easy to reference it in a provider block and forget the declaration itself — this happened during initial setup of this project).

---

## 5. Grant ECR push access

Per the Learner Lab guide, `LabRole` only has read access to ECR. Your GitHub Actions CI pipeline authenticates using the **session credentials** directly (Secrets Manager-style access keys, not an assumed role), so it inherits your **console user's** write access — no separate role/policy step needed here, unlike the Azure `AcrPush` role assignment. Confirm push works once the pipeline runs; if it fails with `AccessDenied`, the session credentials in GitHub secrets are likely stale — refresh them.

---

## 6. Connect to the cluster and bootstrap Argo CD + the secret

```bash
aws eks update-kubeconfig --region us-east-1 --name eks-flaskapp-dev
kubectl get nodes
```

Confirm the CSI driver DaemonSets and the CloudWatch/Fluent Bit DaemonSets are running (see `docs/aws/OPERATIONS.md` for the exact commands and known `hostNetwork`/DNS gotchas both required to reach a stable state).

```bash
kubectl apply -f argocd-app-aws.yaml
```

**Secret delivery note:** unlike Azure (Key Vault CSI, live sync), AWS pods receive the DB password via a Terraform-provisioned `kubernetes_secret`, not a `SecretProviderClass`. This is a deliberate, documented divergence — ASCP (the AWS CSI provider) hard-requires IRSA, which Learner Lab's IAM restrictions block. See the root README's Architecture Decisions comparison table for the full explanation. No manual `kubectl apply` of a SecretProviderClass is needed on this side — the Secret is created directly by `terraform apply`.

---

## 7. Verify

```bash
kubectl get secret mysql-secret -n default
kubectl get application flask-app -n argocd
kubectl get pods -n default
```

From here, Argo CD manages everything in `kubernetes/overlays/aws` (plus shared `base/`) automatically on every commit — same as the Azure side.