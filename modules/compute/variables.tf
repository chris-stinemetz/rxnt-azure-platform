variable "resource_group_name" {
  description = "Name of the resource group."
  type        = string
}

variable "location" {
  description = "Azure region."
  type        = string
}

variable "name_prefix" {
  description = "Short prefix used to derive resource names."
  type        = string
}

variable "unique_suffix" {
  description = "Stable suffix appended to globally unique resource names."
  type        = string
}

variable "key_vault_name" {
  description = "Key Vault name used to construct Key Vault reference strings in app settings."
  type        = string
}

variable "app_service_sku" {
  description = "App Service Plan SKU. Standard (S1) or higher required for autoscaling."
  type        = string
  default     = "S1"
}

variable "common_tags" {
  description = "Tags applied to all taggable resources."
  type        = map(string)
}
