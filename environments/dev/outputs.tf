output "resource_group_name" {
  value       = azurerm_resource_group.main.name
  description = "Resource group containing all dev infrastructure."
}

output "acr_login_server" {
  value       = module.compute.acr_login_server
  description = "ACR login server for docker push/pull operations."
}

output "key_vault_name" {
  value       = module.data.key_vault_name
  description = "Key Vault name where application secrets are stored."
}

output "api_app_name" {
  value       = module.compute.api_app_name
  description = "App Service name for the API web app."
}

output "site_app_name" {
  value       = module.compute.site_app_name
  description = "App Service name for the site web app."
}

output "site_url" {
  value       = module.compute.site_url
  description = "Public URL of the site web app."
}

output "api_url" {
  value       = module.compute.api_url
  description = "Public URL of the API web app."
}
