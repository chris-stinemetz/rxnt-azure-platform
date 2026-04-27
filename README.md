# rxnt-azure-platform

Terraform infrastructure for deploying the [RXNT marketing site](https://github.com/RXNT/site-mkt) to Azure Kubernetes Service. Designed as a reusable, production-grade template for containerized app deployments.

## Architecture

```mermaid
graph TD
    subgraph ci["GitHub Actions"]
        TF["terraform.yml\ninfra CD"]
        CD["deploy.yml\napp CD"]
    end
    DEV["Local Terraform\ndev deploys"]

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

    TF -- "terraform apply" --> azure
    DEV -- "terraform apply" --> azure
    CD -- "push images" --> ACR
    CD -- "helm upgrade" --> aks
    ACR -- "image pull" --> aks
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
helm/
  marketing-site/ Helm chart — site + api Deployments, Services, SecretProviderClass, HPA
.github/
  workflows/
    terraform.yml          Plan on PR, apply on merge to main (infra)
    deploy.yml             Build images + helm upgrade on merge to main (app)
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

## Application Deployment (CD)

Application deployments — building images and deploying to AKS — are handled by `.github/workflows/deploy.yml`, which runs automatically on every merge to `main` that changes `helm/**` or the workflow file itself.

The workflow:
1. Authenticates to Azure via OIDC (same `prod` environment gate as the infra apply)
2. Reads `acr_login_server`, `key_vault_name`, and `key_vault_secrets_provider_client_id` from Terraform remote state via `terraform output`
3. Clones [RXNT/site-mkt](https://github.com/RXNT/site-mkt) and builds both images, tagged with `github.sha`
4. Pushes images to ACR
5. Runs `helm upgrade --install` with values populated from Terraform outputs

No values are hardcoded in the workflow — everything comes from Terraform state at deploy time.

### Manual image build and deploy

For local testing after `terraform apply`:

```bash
ACR=$(terraform -chdir=environments/dev output -raw acr_login_server)
KV=$(terraform -chdir=environments/dev output -raw key_vault_name)
CSI_CLIENT=$(terraform -chdir=environments/dev output -raw key_vault_secrets_provider_client_id)
TENANT=$(az account show --query tenantId -o tsv)

az acr login --name $ACR

docker build -f Dockerfile.site -t $ACR/site:latest .
docker push $ACR/site:latest
docker build -f Dockerfile.api -t $ACR/api:latest .
docker push $ACR/api:latest

az aks get-credentials --resource-group rxnt-marketing-rg-dev --name rxntmktdev-aks

helm upgrade --install marketing-site helm/marketing-site \
  --set image.apiRepository=$ACR/api \
  --set image.siteRepository=$ACR/site \
  --set keyVault.name=$KV \
  --set keyVault.tenantId=$TENANT \
  --set keyVault.csiClientId=$CSI_CLIENT
```

## Design Decisions

**AKS over Container Apps** — AKS demonstrates deeper Kubernetes/infrastructure expertise and supports the autoscaling requirement (10am–8pm EST traffic pattern) via VMSS node pools and HPA.

**AcrPull via kubelet managed identity** — AKS pulls images from ACR using a system-assigned identity and role assignment. No registry credentials are stored anywhere.

**CSI driver for secret injection** — The Secrets Store CSI Driver addon on AKS syncs Key Vault secrets to a Kubernetes secret (`app-secrets`). Pods mount a secrets-store volume to trigger the sync, then reference env vars from the K8s secret. No secrets touch the filesystem or environment at build time.

**CSI access policy in the environment, not the module** — The CSI driver creates its own user-assigned managed identity (distinct from the kubelet identity). Granting it a Key Vault access policy requires a reference to both `module.compute` and `module.data` outputs, so it lives in the environment `main.tf` to avoid circular module dependencies.

**Helm for app manifests, separate deploy.yml for CD** — The Terraform `helm` provider cannot reference AKS module outputs in its `provider` block (provider configs are evaluated before modules run). A separate `deploy.yml` workflow is the correct CD boundary: it builds images, reads Terraform outputs from remote state, and runs `helm upgrade`.

**OIDC for CI authentication** — GitHub Actions authenticates to Azure via Workload Identity Federation. No long-lived `client_secret` is stored in GitHub secrets; the federated credential is scoped to a specific repo and branch.

**Key Vault access policy model** — RBAC authorization disabled; the SP gets a direct access policy with only the required secret permissions (`Get`, `List`, `Set`, `Delete`, `Recover`, `Purge`).

**Random suffixes for global uniqueness** — ACR, SQL Server, Redis, and Key Vault names require globally unique Azure names. A `random_string` suffix is appended to avoid collisions across deployments and forks.

**Explicit `depends_on` on subnets and SQL DB** — Azure's control plane can return success on parent resource creation while child API calls briefly 404. Targeted `depends_on` was added only after observing transient failures in real applies — not as a blanket pattern.

**Remote state in East US, infra in Central US** — State storage is independent of the infrastructure it tracks and lives in its own resource group (`rg-terraform-state`) outside Terraform's management, so `terraform destroy` can never touch it.

**Region: Central US** — East US and East US 2 both failed for this subscription (AKS node SKU rejection + SQL `ProvisioningDisabled`). Central US passed both checks; West US 3 is a confirmed fallback.
