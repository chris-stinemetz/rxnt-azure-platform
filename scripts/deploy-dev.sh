#!/usr/bin/env bash
set -euo pipefail

# Usage: ./scripts/deploy-dev.sh [image-tag]
#
#   image-tag  Docker image tag to deploy. Defaults to "latest".
#
# Images are built by the dev-deploy.yml GitHub Actions workflow.
# Run this script to (re)deploy the Helm chart against already-built images.

TAG="${1:-latest}"

REPO_ROOT="$(git rev-parse --show-toplevel)"
cd "$REPO_ROOT"

echo "==> Reading Terraform outputs..."
ACR=$(terraform -chdir=environments/dev output -raw acr_login_server)
KV=$(terraform -chdir=environments/dev output -raw key_vault_name)
CSI_CLIENT=$(terraform -chdir=environments/dev output -raw key_vault_secrets_provider_client_id)
RG=$(terraform -chdir=environments/dev output -raw resource_group_name)
AKS=$(terraform -chdir=environments/dev output -raw aks_cluster_name)
TENANT=$(az account show --query tenantId -o tsv)

echo "    ACR:       $ACR"
echo "    Key Vault: $KV"
echo "    AKS:       $AKS"
echo "    Tag:       $TAG"

echo "==> Getting AKS credentials..."
az aks get-credentials \
  --resource-group "$RG" \
  --name "$AKS" \
  --overwrite-existing

echo "==> Deploying via Helm..."
helm upgrade --install marketing-site helm/marketing-site \
  --namespace marketing --create-namespace \
  --set image.apiRepository="$ACR/api" \
  --set image.siteRepository="$ACR/site" \
  --set image.tag="$TAG" \
  --set keyVault.name="$KV" \
  --set keyVault.tenantId="$TENANT" \
  --set keyVault.csiClientId="$CSI_CLIENT" \
  --wait --timeout 5m

echo "==> Done. Run: kubectl get pods -n marketing"
