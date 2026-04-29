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
  description = "Random suffix appended to globally unique resource names."
  type        = string
}

variable "sql_admin_username" {
  description = "Administrator username for Azure SQL Server."
  type        = string
}

variable "sql_admin_password" {
  description = "Administrator password for Azure SQL Server."
  type        = string
  sensitive   = true
}

variable "common_tags" {
  description = "Tags applied to all taggable resources."
  type        = map(string)
}
