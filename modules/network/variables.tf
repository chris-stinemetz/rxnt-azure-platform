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

variable "common_tags" {
  description = "Tags applied to all taggable resources."
  type        = map(string)
}
