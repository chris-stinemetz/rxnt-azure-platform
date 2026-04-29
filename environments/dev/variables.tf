variable "subscription_id" {
  description = "Azure subscription ID used by the provider."
  type        = string
  default     = null
}

variable "client_id" {
  description = "Service Principal application (client) ID."
  type        = string
  default     = null
}

variable "client_secret" {
  description = "Service Principal client secret."
  type        = string
  sensitive   = true
  default     = null
}

variable "tenant_id" {
  description = "Azure AD tenant ID for the Service Principal."
  type        = string
  default     = null
}

variable "location" {
  description = "Azure region for all resources."
  type        = string
  default     = "Central US"
}

variable "resource_group_name" {
  description = "Resource group name for all dev infrastructure."
  type        = string
  default     = "rxnt-marketing-rg-dev-as"
}

variable "name_prefix" {
  description = "Short prefix used to derive unique Azure resource names."
  type        = string
  default     = "rxntmktdev"
}

variable "name_suffix" {
  description = "Stable suffix appended to globally unique resource names (ACR, SQL, Redis, Key Vault). Fixed per environment to avoid name changes on destroy/re-apply."
  type        = string
  default     = "b5k9m2"
}

variable "sql_admin_username" {
  description = "Administrator username for Azure SQL Server."
  type        = string
  default     = "rxntsqladmin"
}

variable "app_service_sku" {
  description = "App Service Plan SKU. Standard (S1) or higher required for autoscaling."
  type        = string
  default     = "S1"
}

variable "common_tags" {
  description = "Tags applied to all taggable Azure resources."
  type        = map(string)
  default = {
    managed_by  = "terraform"
    project     = "rxnt-marketing-site"
    environment = "dev"
  }
}
