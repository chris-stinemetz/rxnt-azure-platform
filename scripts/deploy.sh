#!/usr/bin/env bash
set -euo pipefail

# Usage: ./scripts/deploy.sh <env> <image_tag>
#   env:       dev | prod
#   image_tag: Docker image tag (e.g. latest, git SHA)
#
# Prerequisites:
#   - terraform applied for the target environment
#   - az login / service principal env vars set
#
# Set SKIP_BUILD=true to skip image build and push (images already in ACR)

ENV="${1:-dev}"
IMAGE_TAG="${2:-latest}"
SKIP_BUILD="${SKIP_BUILD:-false}"

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TF_DIR="${REPO_DIR}/environments/${ENV}"

echo "==> Reading Terraform outputs from ${TF_DIR}"
ACR=$(terraform -chdir="${TF_DIR}" output -raw acr_login_server)
RG=$(terraform -chdir="${TF_DIR}" output -raw resource_group_name)
API_APP=$(terraform -chdir="${TF_DIR}" output -raw api_app_name)
SITE_APP=$(terraform -chdir="${TF_DIR}" output -raw site_app_name)

if [[ "${SKIP_BUILD}" == "true" ]]; then
  echo "==> Skipping image build (SKIP_BUILD=true)"
else
  echo "==> Logging in to ACR: ${ACR}"
  az acr login --name "${ACR%%.*}"

  echo "==> Building and pushing images"
  docker build --platform linux/amd64 -f Dockerfile.site -t "${ACR}/site:${IMAGE_TAG}" .
  docker push "${ACR}/site:${IMAGE_TAG}"

  docker build --platform linux/amd64 -f Dockerfile.api -t "${ACR}/api:${IMAGE_TAG}" .
  docker push "${ACR}/api:${IMAGE_TAG}"
fi

echo "==> Deploying to App Service"
az webapp config container set \
  --name "${API_APP}" \
  --resource-group "${RG}" \
  --docker-image "${ACR}/api:${IMAGE_TAG}"

az webapp config container set \
  --name "${SITE_APP}" \
  --resource-group "${RG}" \
  --docker-image "${ACR}/site:${IMAGE_TAG}"

echo "==> Done."
terraform -chdir="${TF_DIR}" output site_url
