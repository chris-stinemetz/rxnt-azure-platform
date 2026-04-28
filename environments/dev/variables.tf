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
  default     = "rxnt-marketing-rg-dev"
}

variable "name_prefix" {
  description = "Short prefix used to derive unique Azure resource names."
  type        = string
  default     = "rxntmktdev"
}

variable "sql_admin_username" {
  description = "Administrator username for Azure SQL Server."
  type        = string
  default     = "rxntsqladmin"
}

variable "api_image_name" {
  description = "Repository name for API image in ACR."
  type        = string
  default     = "api"
}

variable "api_image_tag" {
  description = "Tag for API image in ACR."
  type        = string
  default     = "latest"
}

variable "site_image_name" {
  description = "Repository name for site image in ACR."
  type        = string
  default     = "site"
}

variable "site_image_tag" {
  description = "Tag for site image in ACR."
  type        = string
  default     = "latest"
}

variable "api_base_url" {
  description = "Base URL the site uses to reach the API service."
  type        = string
  default     = "http://api.marketing.svc.cluster.local"
}

variable "aks_node_count" {
  description = "Node count for the AKS system node pool."
  type        = number
  default     = 1
}

variable "aks_node_vm_size" {
  description = "VM size for AKS system node pool."
  type        = string
  default     = "Standard_D2s_v3"
}

variable "aks_dns_prefix" {
  description = "DNS prefix for AKS cluster API endpoint."
  type        = string
  default     = "rxntmktdev"
}

variable "aks_kubernetes_version" {
  description = "Optional AKS Kubernetes version. Null uses provider default stable version."
  type        = string
  default     = null
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
