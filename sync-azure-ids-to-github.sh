#!/usr/bin/env bash
set -euo pipefail

# --- Subscription & Tenant (same for both pipelines) ---
SUBSCRIPTION_ID=$(az account show --query id -o tsv)
TENANT_ID=$(az account show --query tenantId -o tsv)

echo "Subscription ID: $SUBSCRIPTION_ID"
echo "Tenant ID: $TENANT_ID"

gh secret set AZURE_SUBSCRIPTION_ID --body "$SUBSCRIPTION_ID"
gh secret set AZURE_TENANT_ID --body "$TENANT_ID"

# --- App Pipeline SP (AcrPush) ---
APP_CLIENT_ID=$(az ad app list --display-name "flaskapp-github-oidc" --query "[0].appId" -o tsv)

if [ -z "$APP_CLIENT_ID" ]; then
  echo "ERROR: app pipeline SP not found — check the display-name matches what you created in Phase 0"
  exit 1
fi

echo "App Pipeline Client ID: $APP_CLIENT_ID"
gh secret set AZURE_CLIENT_ID --body "$APP_CLIENT_ID"

# --- Infra Pipeline SP (Contributor) ---
INFRA_CLIENT_ID=$(az ad app list --display-name "terraform-infra-github-oidc" --query "[0].appId" -o tsv)

if [ -z "$INFRA_CLIENT_ID" ]; then
  echo "ERROR: infra pipeline SP not found — check the display-name matches what you created"
  exit 1
fi

echo "Infra Pipeline Client ID: $INFRA_CLIENT_ID"
gh secret set AZURE_INFRA_CLIENT_ID --body "$INFRA_CLIENT_ID"

echo ""
echo "Done. Verify with: gh secret list"