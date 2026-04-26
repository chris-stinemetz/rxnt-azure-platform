output "resource_group_name" {
  value       = azurerm_resource_group.main.name
  description = "Resource group containing all dev infrastructure."
}

output "acr_login_server" {
  value       = module.compute.acr_login_server
  description = "ACR login server for docker push/pull operations."
}

output "aks_cluster_name" {
  value       = module.compute.aks_cluster_name
  description = "AKS cluster name."
}

output "aks_kubelet_identity_object_id" {
  value       = module.compute.aks_kubelet_identity_object_id
  description = "Object ID of AKS kubelet identity."
}

output "key_vault_name" {
  value       = module.data.key_vault_name
  description = "Key Vault name where application secrets are stored."
}
