# Cloud-Native Flask — Operations Cheat Sheet

## Connect to AKS

```bash
az aks get-credentials --resource-group rg-flaskapp-dev --name aks-flaskapp-dev
kubectl get nodes
kubectl cluster-info
```

## Terraform outputs (run from terraform/ directory)

```bash
terraform output                              # show everything
terraform output -raw acr_login_server
terraform output -raw mysql_fqdn
terraform output -raw key_vault_name
terraform output -raw key_vault_uri
terraform output -raw key_vault_tenant_id
terraform output -raw aks_key_vault_csi_client_id
terraform output -raw aks_kubelet_identity_object_id
terraform output -raw vnet_name
terraform output -raw aks_subnet_id
terraform output -raw resource_group_name
```

## Azure identity / role values (for federated credentials, RBAC, SecretProviderClass)

```bash
az account show --query id -o tsv                    # subscription ID
az account show --query tenantId -o tsv               # tenant ID

az ad app list --display-name "flaskapp-github-oidc" --query "[0].appId" -o tsv
az ad app list --display-name "terraform-infra-github-oidc" --query "[0].appId" -o tsv

az ad sp show --id <appId> --query id -o tsv           # object ID from client/app ID

az ad app federated-credential list --id <appId>       # verify federated creds attached

# List federated credentials including claims matching expressions (not visible via az ad app federated-credential list)
OBJECT_ID=$(az ad app show --id <appId> --query id -o tsv)
az rest --method get --url "https://graph.microsoft.com/beta/applications/${OBJECT_ID}/federatedIdentityCredentials"
```

## Key Vault — check/read secrets directly (admin/debug only)

```bash
az keyvault secret list --vault-name kv-flaskapp-dev-xxxx -o table
az keyvault secret show --vault-name kv-flaskapp-dev-xxxx --name mysql-admin-password --query value -o tsv
```

## Kubernetes — verify secrets synced correctly

```bash
kubectl get secret mysql-secret -n default
kubectl get secret mysql-secret -n default -o jsonpath="{.data.MYSQL_DATABASE_PASSWORD}" | base64 -d
kubectl get secretproviderclass -n default
kubectl describe secretproviderclass mysql-password-spc -n default
```

## Pods, deployments, general cluster state

```bash
kubectl get pods -n default
kubectl get pods -n argocd
kubectl get pods -n ingress-nginx
kubectl describe pod <pod-name> -n default
kubectl logs <pod-name> -n default
kubectl logs -f <pod-name> -n default              # follow/tail
kubectl get deployment flask-app -n default
kubectl get events -n default --sort-by='.lastTimestamp'
```

## Verify DB connectivity

```bash
# From your local machine (needs temporary firewall rule first — see below)
mysql -h $(cd terraform && terraform output -raw mysql_fqdn) \
  -u mysqladmin -p --ssl-mode=REQUIRED BucketList

# From inside a running pod (no firewall changes needed, already Azure-internal)
kubectl exec -it <flask-pod-name> -n default -- sh
# then inside the pod, if mysql client is available:
mysql -h $MYSQL_DATABASE_HOST -u $MYSQL_DATABASE_USER -p --ssl-mode=REQUIRED

# One-off temp firewall rule for local access
MY_IP=$(curl -s ifconfig.me)
az mysql flexible-server firewall-rule create \
  --resource-group rg-flaskapp-dev --name mysql-flaskapp-dev \
  --rule-name AllowMyIP --start-ip-address $MY_IP --end-ip-address $MY_IP

# Remove it after
az mysql flexible-server firewall-rule delete \
  --resource-group rg-flaskapp-dev --name mysql-flaskapp-dev \
  --rule-name AllowMyIP --yes
```

## Argo CD

```bash
kubectl get pods -n argocd
kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d
kubectl port-forward svc/argocd-server -n argocd 8080:443
# then open https://localhost:8080  (user: admin)

kubectl get application -n argocd
kubectl describe application flask-app -n argocd
kubectl get application flask-app -n argocd -o jsonpath="{.status.sync.status}"
kubectl get application flask-app -n argocd -o jsonpath="{.status.health.status}"
```

## Ingress — get the public URL

```bash
kubectl get svc -n ingress-nginx ingress-nginx-controller
# look at EXTERNAL-IP column

# If using the Azure DNS label annotation:
#https://flaskapp-dev.westus2.cloudapp.azure.com/
nslookup <project>-<env>.<region>.cloudapp.azure.com
# e.g. nslookup flaskapp-dev.westus2.cloudapp.azure.com

kubectl get ingress -n default
kubectl describe ingress <ingress-name> -n default
```

## Full app smoke test

```bash
curl -I http://<external-ip-or-dns-name>/
curl http://<external-ip-or-dns-name>/showSignUp
```

## GitHub — secrets/variables quick check

```bash
gh secret list
gh variable list
```

## Logs/Monitoring (Azure Monitor)

```bash
terraform output -raw log_analytics_workspace_id
az monitor log-analytics query \
  --workspace $(cd terraform && terraform output -raw log_analytics_workspace_id) \
  --analytics-query "ContainerLog | take 20"
```