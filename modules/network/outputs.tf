output "vnet_id" {
  value       = azurerm_virtual_network.main.id
  description = "ID of the virtual network."
}

output "aks_nodes_subnet_id" {
  value       = azurerm_subnet.aks_nodes.id
  description = "Subnet ID for AKS node pool."
}

output "private_endpoints_subnet_id" {
  value       = azurerm_subnet.private_endpoints.id
  description = "Subnet ID for private endpoints."
}
