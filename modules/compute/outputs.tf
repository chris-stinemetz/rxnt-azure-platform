output "acr_login_server" {
  value       = azurerm_container_registry.main.login_server
  description = "ACR login server for docker push/pull."
}

output "acr_id" {
  value       = azurerm_container_registry.main.id
  description = "ACR resource ID."
}

output "api_app_name" {
  value       = azurerm_linux_web_app.api.name
  description = "App Service name for the API web app."
}

output "site_app_name" {
  value       = azurerm_linux_web_app.site.name
  description = "App Service name for the site web app."
}

output "api_url" {
  value       = "https://${azurerm_linux_web_app.api.default_hostname}"
  description = "Public URL of the API web app."
}

output "site_url" {
  value       = "https://${azurerm_linux_web_app.site.default_hostname}"
  description = "Public URL of the site web app."
}

output "api_principal_id" {
  value       = azurerm_linux_web_app.api.identity[0].principal_id
  description = "Principal ID of the API web app managed identity (used for Key Vault access policy)."
}

output "site_principal_id" {
  value       = azurerm_linux_web_app.site.identity[0].principal_id
  description = "Principal ID of the site web app managed identity (used for Key Vault access policy)."
}
