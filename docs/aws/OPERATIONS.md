# Cloud-Native Flask (AWS) — Operations Reference

> Before anything in this file: refresh Learner Lab credentials if it's been a while since your last session.
> ```bash
> ./refresh-aws-lab-creds.sh
> aws sts get-caller-identity   # confirms credentials are actually valid before you proceed
> ```

## Part 1: First-Time Cluster Bootstrap (do these in order)

### 1. Connect to EKS

```bash
aws eks update-kubeconfig --region us-east-1 --name eks-flaskapp-dev
kubectl get nodes
kubectl cluster-info
```

### 2. Confirm the CSI driver + AWS secrets provider are running

```bash
kubectl get pods -n kube-system | grep csi-secrets
```
Both `secrets-store-csi-driver` and `secrets-provider-aws` DaemonSets should show `Running` on every node. If missing, the Helm releases in `secrets-csi-driver.tf` haven't applied yet — check `terraform apply` output.

### 3. Get the Secrets Manager ARN for `secret-provider-class.yml`

```bash
cd terraform/aws
terraform output -raw secrets_manager_secret_arn
```

**Edit `secret-provider-class.yml` (AWS version) and paste the ARN in:**
```yaml
  parameters:
    objects: |
      - objectName: "<value from secrets_manager_secret_arn>"
        objectType: "secretsmanager"
```
No identity/role field needed — pods inherit Secrets Manager read access via the node's `LabRole` instance profile automatically.

### 4. Apply the SecretProviderClass manually

```bash
kubectl apply -f secret-provider-class-aws.yml
kubectl get secretproviderclass -n default
kubectl describe secretproviderclass mysql-password-spc -n default
```

### 5. Apply the Argo CD Application manifest

First confirm Argo CD itself is running on this cluster (installed via Terraform's `helm_release`, same as AKS):
```bash
kubectl get pods -n argocd
```

```bash
kubectl apply -f argocd-app-aws.yaml
```

### 6. Get the Argo CD admin password and access the UI

```bash
kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d
kubectl port-forward svc/argocd-server -n argocd 8080:443
```
Open `https://localhost:8080` — log in as `admin`.

### 7. Confirm the app synced and the secret materialized

```bash
kubectl get application flask-app -n argocd
kubectl get secret mysql-secret -n default
kubectl get pods -n default
```

From here, Argo CD manages everything in `kubernetes/overlays/aws` (plus shared `base/`) automatically on every commit.

---

## Part 2: Ongoing Reference Commands

### Terraform outputs (run from terraform/aws directory)

```bash
terraform output
terraform output -raw ecr_repository_url
terraform output -raw eks_cluster_name
terraform output -raw eks_kube_config_command
terraform output -raw rds_endpoint
terraform output -raw secrets_manager_secret_arn
```

### AWS identity / credentials

```bash
aws sts get-caller-identity
aws configure list
cat ~/.aws/credentials   # confirm session hasn't gone stale
```

### ECR — check images, confirm push worked

```bash
aws ecr describe-repositories --repository-names flaskapp-flask-app
aws ecr list-images --repository-name flaskapp-flask-app
aws ecr describe-image-scan-findings --repository-name flaskapp-flask-app --image-id imageTag=<tag>
```

### Secrets Manager — check/read secret directly (admin/debug only)

```bash
aws secretsmanager list-secrets
aws secretsmanager get-secret-value --secret-id flaskapp-mysql-password-dev --query SecretString --output text
```

### Kubernetes — verify secret synced correctly

```bash
kubectl get secret mysql-secret -n default
kubectl get secret mysql-secret -n default -o jsonpath="{.data.MYSQL_DATABASE_PASSWORD}" | base64 -d
kubectl get secretproviderclass -n default
```

### Pods, deployments, general cluster state

```bash
kubectl get pods -n default
kubectl get pods -n argocd
kubectl get pods -n ingress-nginx
kubectl describe pod <pod-name> -n default
kubectl logs <pod-name> -n default
kubectl logs -f <pod-name> -n default
kubectl get deployment flask-app -n default
kubectl get events -n default --sort-by='.lastTimestamp'
```

### Verify RDS connectivity

```bash
# RDS security group only allows traffic from the EKS cluster's security group —
# no local-machine access without temporarily opening the SG, unlike Azure's
# broader firewall rule. Easiest verification is from inside a pod:
kubectl exec -it <flask-pod-name> -n default -- sh
# then inside the pod:
mysql -h $MYSQL_DATABASE_HOST -u $MYSQL_DATABASE_USER -p BucketList

# To allow temporary local access instead:
MY_IP=$(curl -s ifconfig.me)
aws ec2 authorize-security-group-ingress \
  --group-id <mysql-sg-id> \
  --protocol tcp --port 3306 --cidr ${MY_IP}/32

# Remove it after
aws ec2 revoke-security-group-ingress \
  --group-id <mysql-sg-id> \
  --protocol tcp --port 3306 --cidr ${MY_IP}/32
```

### Argo CD (ongoing)

```bash
kubectl get pods -n argocd
kubectl port-forward svc/argocd-server -n argocd 8080:443
kubectl get application -n argocd
kubectl describe application flask-app -n argocd
kubectl get application flask-app -n argocd -o jsonpath="{.status.sync.status}"
kubectl get application flask-app -n argocd -o jsonpath="{.status.health.status}"
```

### Ingress — get the public URL (NLB)

```bash
kubectl get svc -n ingress-nginx ingress-nginx-controller
# EXTERNAL-IP column shows an NLB hostname (*.elb.amazonaws.com), not a bare IP —
# different from Azure's DNS-label pattern, this is AWS's native NLB DNS name.

kubectl get ingress -n default
kubectl describe ingress flask-app-ingress -n default
```

### Full app smoke test

```bash
NLB_HOST=$(kubectl get svc -n ingress-nginx ingress-nginx-controller -o jsonpath="{.status.loadBalancer.ingress[0].hostname}")
curl -I http://$NLB_HOST/
curl http://$NLB_HOST/showSignUp
```

### GitHub — secrets/variables quick check

```bash
gh secret list
gh variable list
```

### CloudWatch — quick log check

```bash
aws logs tail /aws/eks/eks-flaskapp-dev/cluster --follow
```

### Credential refresh (the recurring one)

```bash
./refresh-aws-lab-creds.sh
```
Run this whenever a pipeline or local `terraform`/`kubectl`/`aws` command starts failing with an auth error — almost always means the Learner Lab session expired.