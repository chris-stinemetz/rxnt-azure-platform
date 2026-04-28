# rxnt-azure-platform

Terraform infrastructure for deploying the [RXNT marketing site](https://github.com/RXNT/site-mkt) to Azure Kubernetes Service. Designed as a reusable, production-grade template for containerized app deployments.

## Architecture

```mermaid
graph TD
    subgraph sources["Deployment"]
        TF["GitHub Actions\nterraform.yml"]
        CD["scripts/deploy.sh"]
        DEV["Local Terraform\ndev only"]
    end

    subgraph azure["Azure — Central US"]
        ACR["ACR"]
        subgraph aks["AKS"]
            site["site"]
            api["api"]
            CSI["CSI Driver"]
        end
        SQL[("Azure SQL")]
        Redis[("Redis")]
        KV["Key Vault"]
    end

    TF --> azure
    DEV --> azure
    CD -- "push images" --> ACR
    CD --> aks
    ACR --> aks
    api --> SQL
    site --> Redis
    CSI -- "read secrets" --> KV
```

**Two containerized services:**

| Service | Purpose |
|---------|---------|
| `site` | Frontend — serves "hello world" + current date, cached in Redis (5s TTL) |
| `api`  | Backend — reads from Azure SQL Server |

**Azure resources:**

| Resource | SKU | Notes |
|----------|-----|-------|
| AKS | `Standard_D2s_v3` nodes | VMSS node pool for autoscaling |
| ACR | Basic | AKS pulls via kubelet managed identity — no registry credentials stored |
| Azure SQL | Basic DTU | |
| Redis | Basic C0 | |
| Key Vault | Standard | Stores all three connection strings |
| VNet | `10.20.0.0/16` | AKS nodes `/23`, private endpoints `/24` |

## Repository Structure

```
modules/
  network/        VNet + subnets
  data/           SQL, Redis, Key Vault + secrets
  compute/        AKS, ACR, AcrPull role assignment, CSI driver addon
environments/
  dev/            Local apply — lightweight defaults (1 node)
  prod/           GitHub Actions deploy on merge to main (2 nodes)
k8s/
  namespace.yaml            marketing namespace
  secret-provider-class.yaml  CSI SecretProviderClass — syncs Key Vault secrets to K8s secret
  api-deployment.yaml       API deployment (image, env vars, secrets-store volume mount)
  api-service.yaml          ClusterIP — internal only
  site-deployment.yaml      Site deployment (image, env vars, secrets-store volume mount)
  site-service.yaml         LoadBalancer — external traffic
  hpa.yaml                  HPA for both deployments (CPU 50%, 1–5 replicas)
scripts/
  deploy.sh                 Build images, push to ACR, envsubst manifests, kubectl apply
.github/
  workflows/
    terraform.yml          Plan on PR, apply on merge to main (infra)
    terraform-destroy.yml  Manual destroy with confirmation gate
```

## Prerequisites

- [Terraform](https://developer.hashicorp.com/terraform/install) >= 1.14
- [Azure CLI](https://learn.microsoft.com/en-us/cli/azure/install-azure-cli)
- An Azure subscription
- A Service Principal with Contributor + User Access Administrator roles (see below)

### Create the Service Principal

```bash
az ad sp create-for-rbac --name rxnt-assessment-sp --role Contributor \
  --scopes /subscriptions/<subscription-id>

# Grant User Access Administrator so Terraform can assign AcrPull to the kubelet identity
az role assignment create \
  --assignee <sp-client-id> \
  --role "User Access Administrator" \
  --scope /subscriptions/<subscription-id>
```

## Local Dev Deployment

```bash
cd environments/dev

# Create terraform.tfvars from the example and fill in your SP credentials
cp terraform.tfvars.example terraform.tfvars
# Edit terraform.tfvars with your subscription_id, client_id, client_secret, tenant_id

terraform init
terraform plan
terraform apply

# Get AKS credentials after apply
az aks get-credentials --resource-group rxnt-marketing-rg-dev --name rxntmktdev-aks
```

Terraform automatically loads `terraform.tfvars` when it exists in the working directory — no `-var-file` flag needed.

Always run `terraform destroy` between test iterations to stay within free tier limits.

## Production Deployment (GitHub Actions)

Production deploys run automatically via GitHub Actions — `terraform plan` on every PR, `terraform apply` on merge to `main`. No secrets are stored in GitHub; authentication uses OIDC (Workload Identity Federation).

No `terraform.tfvars` is used for prod. Auth comes from the three `ARM_*` environment variables set in GitHub Actions secrets, and all other variables have production defaults defined in `environments/prod/variables.tf`.

### One-time setup

**1. Bootstrap remote state storage**

```bash
az group create --name rg-terraform-state --location eastus

az storage account create \
  --name rxntterraformstate \
  --resource-group rg-terraform-state \
  --location eastus \
  --sku Standard_LRS

az storage container create --name tfstate --account-name rxntterraformstate
```

The storage account is intentionally created in East US rather than Central US (the infrastructure region). This keeps it independent of the infrastructure it tracks — if you destroy or migrate an environment, the state is unaffected. It also lives in its own resource group (`rg-terraform-state`) outside of Terraform's management so `terraform destroy` can never touch it.

Then uncomment the `backend "azurerm"` block in `environments/prod/providers.tf` and run `terraform init` once to migrate state.

**2. Add federated credentials to the Service Principal**

Three credentials are required — the OIDC subject claim differs between event types so a single credential cannot cover all cases.

In the Azure Portal, navigate to **App registrations → rxnt-assessment-sp → Certificates & secrets → Federated credentials → Add credential** and add all three:

| Field | Credential 1 | Credential 2 | Credential 3 |
|-------|-------------|-------------|-------------|
| Scenario | GitHub Actions | GitHub Actions | GitHub Actions |
| Organization | your GitHub username | your GitHub username | your GitHub username |
| Repository | `rxnt-azure-platform` | `rxnt-azure-platform` | `rxnt-azure-platform` |
| Entity type | Pull request | Branch | Environment |
| Branch / Environment | — | `main` | `prod` |
| Name | `github-actions-pr` | `github-actions-main` | `github-actions-environment-prod` |

Leave Issuer and Audience at their defaults for all three.

- **Pull request** — Plan job on PR events
- **Branch (main)** — Plan job when re-run on a merged commit
- **Environment (prod)** — Apply job running in the `prod` GitHub Environment after approval

**3. Add GitHub Actions secrets**

In your repo: **Settings → Secrets and variables → Actions → New repository secret**

| Secret name | Where to find the value |
|-------------|------------------------|
| `AZURE_CLIENT_ID` | SP application (client) ID |
| `AZURE_TENANT_ID` | Azure AD tenant ID |
| `AZURE_SUBSCRIPTION_ID` | Azure subscription ID |

No `client_secret` is needed — the federated credential handles authentication via OIDC token exchange.

**4. Configure the prod environment with a required reviewer**

In your repo: **Settings → Environments → New environment** → name it `prod` → add yourself (or a teammate) as a required reviewer.

This creates a manual approval gate on the apply job — merging to main triggers the plan automatically, but apply pauses and waits for a human to approve before any infrastructure changes run.

**5. Push to trigger the workflow**

The workflow runs on any push or PR that changes `environments/prod/**` or `modules/**`.

On a **pull request**: the `Plan` job runs and posts the Terraform plan as a comment.

On **merge to main**: the `Plan` job runs first, then the `Apply` job pauses for reviewer approval. Once approved, it applies the exact plan that was reviewed — not a fresh one.

## Destroying Infrastructure

A separate manually-triggered workflow handles destroy so it can never run accidentally.

**Actions → Terraform Destroy → Run workflow**, then:

1. Select the environment (`dev` or `prod`)
2. Type `destroy` in the confirmation field
3. Click **Run workflow**

The job aborts immediately if the confirmation input is anything other than `destroy`.

The `prod` environment required reviewer (configured in step 4 above) also applies here — a second person must approve before the destroy job executes against prod.

## Application Deployment

After `terraform apply`, deploy the application with `scripts/deploy.sh`. The script reads all required values from Terraform outputs at runtime — no credentials or names are hardcoded.

```bash
# Get AKS credentials
az aks get-credentials --resource-group rxnt-marketing-rg-dev --name rxntmktdev-aks

# Deploy (builds images, pushes to ACR, applies all k8s/ manifests)
./scripts/deploy.sh dev latest

# Deploy a specific git SHA tag
./scripts/deploy.sh dev abc1234
```

The script:
1. Reads `acr_login_server`, `key_vault_name`, `tenant_id`, and `key_vault_secrets_provider_client_id` from `terraform output`
2. Builds both Docker images for `linux/amd64` and pushes them to ACR
3. Applies `k8s/namespace.yaml`
4. Runs `envsubst` to substitute `${ACR}`, `${IMAGE_TAG}`, `${CSI_CLIENT_ID}`, `${KEY_VAULT_NAME}`, and `${KEY_VAULT_TENANT_ID}` into the manifests, then pipes each through `kubectl apply`
5. Waits for both rollouts to complete and prints the site's external IP

The Kubernetes manifests in `k8s/` use plain YAML with `envsubst` placeholders for environment-specific values. No Helm or templating engine is required.

## Open Items

- **SP least-privilege (prod bootstrap)** — `User Access Administrator` is scoped to `rxnt-marketing-rg-dev` for dev. For prod, the role assignment can't be pre-scoped to the resource group before it exists. Remediation: pre-create the prod resource group, add the scoped assignment, then `terraform import` the group before the first apply. Until then, subscription-scope `User Access Administrator` is required as a one-time bootstrap.
- **KEDA for time-window autoscaling** — HPA is in place with CPU-based scaling (50% target, 1–5 replicas). Adding KEDA with a cron scaler would pre-scale before the 10am–8pm EST traffic window rather than reacting to it after the fact.

## Design Decisions

**AKS over Container Apps** — AKS demonstrates deeper Kubernetes/infrastructure expertise and supports the autoscaling requirement (10am–8pm EST traffic pattern) via VMSS node pools and HPA.

**AcrPull via kubelet managed identity** — AKS pulls images from ACR using a system-assigned identity and role assignment. No registry credentials are stored anywhere.

**CSI driver for secret injection** — The Secrets Store CSI Driver addon on AKS syncs Key Vault secrets to a Kubernetes secret (`app-secrets`). Pods mount a secrets-store volume to trigger the sync, then reference env vars from the K8s secret. No secrets touch the filesystem or environment at build time.

**CSI access policy in the environment, not the module** — The CSI driver creates its own user-assigned managed identity (distinct from the kubelet identity). Granting it a Key Vault access policy requires a reference to both `module.compute` and `module.data` outputs, so it lives in the environment `main.tf` to avoid circular module dependencies.

**Plain K8s manifests with envsubst** — App manifests live in `k8s/` as plain YAML with `${VAR}` placeholders. `envsubst` substitutes environment-specific values (ACR login server, Key Vault name, CSI client ID) at deploy time, keeping the manifests readable and free of templating engine dependencies. `scripts/deploy.sh` reads all values from `terraform output` so nothing is hardcoded.

**OIDC for CI authentication** — GitHub Actions authenticates to Azure via Workload Identity Federation. No long-lived `client_secret` is stored in GitHub secrets; the federated credential is scoped to a specific repo and branch.

**Key Vault access policy model** — RBAC authorization disabled; the SP gets a direct access policy with only the required secret permissions (`Get`, `List`, `Set`, `Delete`, `Recover`, `Purge`). The SP policy is defined inline on the Key Vault resource (required to bootstrap secret creation in the same module), while the CSI driver policy is a separate `azurerm_key_vault_access_policy` resource in the environment. `lifecycle { ignore_changes = [access_policy] }` on the Key Vault prevents Terraform from treating the externally-managed CSI policy as drift and removing it on every plan.

**Random suffixes for global uniqueness** — ACR, SQL Server, Redis, and Key Vault names require globally unique Azure names. A `random_string` suffix is appended to avoid collisions across deployments and forks.

**Explicit `depends_on` on subnets and SQL DB** — Azure's control plane can return success on parent resource creation while child API calls briefly 404. Targeted `depends_on` was added only after observing transient failures in real applies — not as a blanket pattern.

**Remote state in East US, infra in Central US** — State storage is independent of the infrastructure it tracks and lives in its own resource group (`rg-terraform-state`) outside Terraform's management, so `terraform destroy` can never touch it.

**Region: Central US** — East US and East US 2 both failed for this subscription (AKS node SKU rejection + SQL `ProvisioningDisabled`). Central US passed both checks; West US 3 is a confirmed fallback.
