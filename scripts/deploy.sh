#!/usr/bin/env bash
set -euo pipefail

# Usage: ./scripts/deploy.sh <env> <image_tag>
#   env:       dev | prod
#   image_tag: Docker image tag (e.g. latest, git SHA)
#
# Prerequisites:
#   - terraform applied for the target environment
#   - az login / service principal env vars set
#   - kubectl context pointing at the target cluster

ENV="${1:-dev}"
IMAGE_TAG="${2:-latest}"
SKIP_BUILD="${SKIP_BUILD:-false}"

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TF_DIR="${REPO_DIR}/environments/${ENV}"
K8S_DIR="${REPO_DIR}/k8s"

echo "==> Reading Terraform outputs from ${TF_DIR}"
export ACR=$(terraform -chdir="${TF_DIR}" output -raw acr_login_server)
export KEY_VAULT_NAME=$(terraform -chdir="${TF_DIR}" output -raw key_vault_name)
export KEY_VAULT_TENANT_ID=$(terraform -chdir="${TF_DIR}" output -raw tenant_id)
export CSI_CLIENT_ID=$(terraform -chdir="${TF_DIR}" output -raw key_vault_secrets_provider_client_id)
export IMAGE_TAG

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

echo "==> Applying Kubernetes manifests"
kubectl apply -f "${K8S_DIR}/namespace.yaml"

envsubst < "${K8S_DIR}/secret-provider-class.yaml" | kubectl apply -f -
envsubst < "${K8S_DIR}/api-deployment.yaml"        | kubectl apply -f -
kubectl apply -f "${K8S_DIR}/api-service.yaml"

envsubst < "${K8S_DIR}/site-deployment.yaml" | kubectl apply -f -
kubectl apply -f "${K8S_DIR}/site-service.yaml"

kubectl apply -f "${K8S_DIR}/hpa.yaml"

echo "==> Waiting for rollout"
kubectl rollout status deployment/api  -n marketing --timeout=120s
kubectl rollout status deployment/site -n marketing --timeout=120s

echo "==> Done. External IP:"
kubectl get svc site -n marketing
