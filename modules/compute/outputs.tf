output "acr_login_server" {
  value       = azurerm_container_registry.main.login_server
  description = "ACR login server for docker push/pull."
}

output "acr_id" {
  value       = azurerm_container_registry.main.id
  description = "ACR resource ID."
}

output "aks_cluster_name" {
  value       = azurerm_kubernetes_cluster.main.name
  description = "AKS cluster name."
}

output "aks_kubelet_identity_object_id" {
  value       = azurerm_kubernetes_cluster.main.kubelet_identity[0].object_id
  description = "Object ID of AKS kubelet identity used for ACR pull."
}

output "key_vault_secrets_provider_client_id" {
  value       = azurerm_kubernetes_cluster.main.key_vault_secrets_provider[0].secret_identity[0].client_id
  description = "Client ID of the CSI driver managed identity (used in SecretProviderClass)."
}

output "key_vault_secrets_provider_object_id" {
  value       = azurerm_kubernetes_cluster.main.key_vault_secrets_provider[0].secret_identity[0].object_id
  description = "Object ID of the CSI driver managed identity (used for Key Vault access policy)."
}
