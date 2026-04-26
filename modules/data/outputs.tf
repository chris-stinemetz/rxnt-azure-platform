output "key_vault_name" {
  value       = azurerm_key_vault.main.name
  description = "Key Vault name where application secrets are stored."
}

output "key_vault_id" {
  value       = azurerm_key_vault.main.id
  description = "Key Vault resource ID."
}

output "sql_server_fqdn" {
  value       = azurerm_mssql_server.main.fully_qualified_domain_name
  description = "Fully qualified domain name of the SQL Server."
}

output "redis_primary_connection_string" {
  value       = azurerm_redis_cache.main.primary_connection_string
  description = "Primary connection string for Redis cache."
  sensitive   = true
}
