terraform {
  required_version = ">= 1.14.9"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.70.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.7.2"
    }
  }

  # Remote state for prod. Run `terraform init` after creating the storage account.
  backend "azurerm" {
    resource_group_name  = "rg-terraform-state"
    storage_account_name = "rxntterraformstate"
    container_name       = "tfstate"
    key                  = "prod/terraform.tfstate"
  }
}

provider "azurerm" {
  features {}

  # use_oidc lets CI authenticate via Workload Identity Federation.
  # When ARM_USE_OIDC=true and ARM_* vars are set, client_secret is not needed.
  use_oidc        = true
  subscription_id = var.subscription_id
  client_id       = var.client_id
  client_secret   = var.client_secret
  tenant_id       = var.tenant_id
}
