# rxnt-azure-platform

Terraform infrastructure for deploying the [RXNT marketing site](https://github.com/RXNT/site-mkt) to Azure App Service. Designed as a reusable, production-grade template for containerized app deployments.

## Architecture

```
                        ┌─────────────────────────────────┐
                        │        Azure (Central US)        │
                        │                                  │
   GitHub Actions  ───► │  ACR  ──►  App Service Plan     │
   (build images)       │            ├─ site (container)   │
                        │            └─ api  (container)   │
   Local terraform ───► │                                  │
   (dev deploys)        │  Azure SQL  ◄─ api               │
                        │  Redis      ◄─ site              │
                        │  Key Vault  ◄─ both              │
                        └─────────────────────────────────┘
```

**Two containerized services:**

| Service | Purpose |
|---------|---------|
| `site` | Frontend — serves "hello world" + current date, cached in Redis (5s TTL) |
| `api`  | Backend — reads from Azure SQL Server |

**Azure resources:**

| Resource | SKU | Notes |
|----------|-----|-------|
| App Service Plan | S1 (Linux) | Shared by both apps; S1 required for autoscaling |
| ACR | Basic | Apps pull via managed identity — no registry credentials stored |
| Azure SQL | Basic DTU | |
| Redis | Basic C0 | |
| Key Vault | Standard | Stores connection strings; accessed via Key Vault references |

## Repository Structure

```
modules/
  data/           SQL, Redis, Key Vault + secrets
  compute/        ACR, App Service Plan, Web Apps, autoscale, AcrPull assignments
environments/
  dev/            Local apply — terraform.tfvars for SP creds
  prod/           GitHub Actions deploy on merge to main (OIDC auth)
scripts/
  deploy.sh       Push container images to ACR, update App Service container config
.github/
  workflows/
    terraform.yml          Plan on PR, apply on merge to main (infra)
    terraform-destroy.yml  Manual destroy with confirmation gate
    build.yml              Manually triggered — builds images on amd64 runners, pushes to ACR
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

# Grant User Access Administrator so Terraform can assign AcrPull to the web app identities
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
```

Terraform automatically loads `terraform.tfvars` when it exists in the working directory — no `-var-file` flag needed.

Always run `terraform destroy` between test iterations to stay within free tier limits.

## Production Deployment (GitHub Actions)

Production deploys run automatically via GitHub Actions — `terraform plan` on every PR, `terraform apply` on merge to `main`. No secrets are stored in GitHub; authentication uses OIDC (Workload Identity Federation).

No `terraform.tfvars` is used for prod. Auth comes from the `ARM_*` environment variables set in GitHub Actions secrets, and all other variables have production defaults defined in `environments/prod/variables.tf`.

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

The storage account lives in its own resource group outside of Terraform's management so `terraform destroy` can never touch it.

**2. Add federated credentials to the Service Principal**

In the Azure Portal, navigate to **App registrations → rxnt-assessment-sp → Certificates & secrets → Federated credentials → Add credential** and add all three:

| Field | Credential 1 | Credential 2 | Credential 3 |
|-------|-------------|-------------|-------------|
| Scenario | GitHub Actions | GitHub Actions | GitHub Actions |
| Organization | your GitHub username | your GitHub username | your GitHub username |
| Repository | `rxnt-azure-platform` | `rxnt-azure-platform` | `rxnt-azure-platform` |
| Entity type | Pull request | Branch | Environment |
| Branch / Environment | — | `main` | `prod` |
| Name | `github-actions-pr` | `github-actions-main` | `github-actions-environment-prod` |

**3. Add GitHub Actions secrets**

In your repo: **Settings → Secrets and variables → Actions → New repository secret**

| Secret name | Where to find the value |
|-------------|------------------------|
| `AZURE_CLIENT_ID` | SP application (client) ID |
| `AZURE_TENANT_ID` | Azure AD tenant ID |
| `AZURE_SUBSCRIPTION_ID` | Azure subscription ID |

**4. Configure the prod environment with a required reviewer**

In your repo: **Settings → Environments → New environment** → name it `prod` → add yourself as a required reviewer.

**5. Push to trigger the workflow**

The workflow runs on any push or PR that changes `environments/prod/**` or `modules/**`.

On a **pull request**: the `Plan` job runs and posts the Terraform plan as a comment.

On **merge to main**: the `Plan` job runs first, then the `Apply` job pauses for reviewer approval.

## Destroying Infrastructure

**Actions → Infra — Destroy → Run workflow**, then:

1. Select the environment (`dev` or `prod`)
2. Type `destroy` in the confirmation field
3. Click **Run workflow**

## Application Deployment

Application deployment is a two-step process: build images in CI, then update the App Service container config.

**Step 1 — Build images (GitHub Actions)**

**Actions → App — Build Images → Run workflow**, select the target environment and image tag. This builds both images on native `linux/amd64` runners and pushes them to the environment's ACR. No local Docker required.

**Step 2 — Deploy**

```bash
# Deploy (images already in ACR from step 1)
SKIP_BUILD=true ./scripts/deploy.sh dev latest

# Or build locally and deploy in one step (slow on Apple Silicon)
./scripts/deploy.sh dev latest
```

`deploy.sh` reads `acr_login_server`, `resource_group_name`, `api_app_name`, and `site_app_name` from `terraform output` and runs `az webapp config container set` to update both apps. App Service pulls the new image and restarts automatically.

## Open Items

- **SP least-privilege** — The SP holds subscription-scope `User Access Administrator` to allow Terraform to create AcrPull role assignments on the web app identities. Can be tightened post-deploy by scoping to the resource group or using an ABAC condition limiting assignment to only the AcrPull role.
- **KEDA for time-window autoscaling** — CPU-based autoscale is in place (50% threshold, 1–5 instances). KEDA with a cron scaler would pre-scale before the 10am–8pm EST traffic window rather than reacting after the fact.

## Design Decisions

**App Service over AKS** — App Service matches the team's current operational expertise while still supporting containerized workloads, autoscaling, and managed identity auth. Lower operational overhead than a Kubernetes cluster.

**AcrPull via web app managed identity** — Each web app has a system-assigned identity with AcrPull on ACR. No registry credentials stored anywhere. `container_registry_use_managed_identity = true` in `site_config` enables this at the App Service level.

**Key Vault references in app settings** — Connection strings are stored in Key Vault and referenced in app settings using `@Microsoft.KeyVault(VaultName=...;SecretName=...)` syntax. App Service resolves these at runtime using the web app's managed identity — no secrets in Terraform state or environment variables.

**Key Vault access policies in the environment, not the module** — The web app managed identities are created in the compute module, but granting them Key Vault access requires referencing both `module.compute` and `module.data` outputs. This lives in the environment `main.tf` to avoid circular module dependencies.

**OIDC for CI authentication** — GitHub Actions authenticates to Azure via Workload Identity Federation. No long-lived `client_secret` is stored in GitHub secrets; the federated credential is scoped to a specific repo and branch.

**Stable name suffixes per environment** — ACR, SQL, Redis, and Key Vault names require globally unique Azure names. Each environment declares a fixed `name_suffix` variable so resource names are stable across destroy/re-apply cycles. Images pushed to ACR remain valid after a full infra rebuild.

**Explicit `depends_on` on SQL DB** — Azure's control plane can return success on parent resource creation while child API calls briefly 404. Targeted `depends_on` was added only after observing transient failures in real applies.

**Remote state in East US, infra in Central US** — State storage is independent of the infrastructure it tracks and lives in its own resource group (`rg-terraform-state`) outside Terraform's management, so `terraform destroy` can never touch it.

**Region: Central US** — East US and East US 2 both failed for this subscription (SKU rejection + SQL `ProvisioningDisabled`). Central US passed; West US 3 is a confirmed fallback.
