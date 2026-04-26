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

variable "aks_nodes_subnet_id" {
  description = "Subnet ID for the AKS node pool."
  type        = string
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
}

variable "aks_kubernetes_version" {
  description = "Optional AKS Kubernetes version. Null uses provider default stable version."
  type        = string
  default     = null
}

variable "common_tags" {
  description = "Tags applied to all taggable resources."
  type        = map(string)
}
