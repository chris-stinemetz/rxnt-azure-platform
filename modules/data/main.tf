locals {
  sql_server_name = lower(replace("${var.name_prefix}${var.unique_suffix}sql", "-", ""))
  redis_name      = lower(replace("${var.name_prefix}-${var.unique_suffix}-redis", "_", "-"))
  key_vault_name  = lower(replace("${var.name_prefix}-${var.unique_suffix}-kv", "_", "-"))

  db_connection_string = "Server=tcp:${azurerm_mssql_server.main.fully_qualified_domain_name},1433;Initial Catalog=${azurerm_mssql_database.main.name};Persist Security Info=False;User ID=${azurerm_mssql_server.main.administrator_login};Password=${var.sql_admin_password};MultipleActiveResultSets=False;Encrypt=True;TrustServerCertificate=False;Connection Timeout=30;"
}

data "azurerm_client_config" "current" {}

resource "azurerm_mssql_server" "main" {
  name                         = local.sql_server_name
  resource_group_name          = var.resource_group_name
  location                     = var.location
  version                      = "12.0"
  administrator_login          = var.sql_admin_username
  administrator_login_password = var.sql_admin_password
  minimum_tls_version          = "1.2"
  tags                         = var.common_tags
}

resource "azurerm_mssql_database" "main" {
  name      = "marketing-db"
  server_id = azurerm_mssql_server.main.id
  sku_name  = "Basic"
  tags      = var.common_tags

  depends_on = [azurerm_mssql_server.main]
}

resource "azurerm_mssql_firewall_rule" "allow_azure_services" {
  name             = "AllowAzureServices"
  server_id        = azurerm_mssql_server.main.id
  start_ip_address = "0.0.0.0"
  end_ip_address   = "0.0.0.0"
}

resource "azurerm_redis_cache" "main" {
  name                          = local.redis_name
  location                      = var.location
  resource_group_name           = var.resource_group_name
  capacity                      = 0
  family                        = "C"
  sku_name                      = "Basic"
  non_ssl_port_enabled          = false
  minimum_tls_version           = "1.2"
  public_network_access_enabled = true
  redis_version                 = 6
  tags                          = var.common_tags
}

resource "azurerm_key_vault" "main" {
  name                          = local.key_vault_name
  location                      = var.location
  resource_group_name           = var.resource_group_name
  tenant_id                     = data.azurerm_client_config.current.tenant_id
  sku_name                      = "standard"
  soft_delete_retention_days    = 7
  purge_protection_enabled      = false
  rbac_authorization_enabled    = false
  public_network_access_enabled = true
  tags                          = var.common_tags

  access_policy {
    tenant_id = data.azurerm_client_config.current.tenant_id
    object_id = data.azurerm_client_config.current.object_id

    key_permissions = ["Get", "List"]

    secret_permissions = [
      "Get",
      "List",
      "Set",
      "Delete",
      "Recover",
      "Purge",
    ]
  }

  lifecycle {
    ignore_changes = [access_policy]
  }
}

resource "azurerm_key_vault_secret" "redis_connection_string" {
  name         = "redis-connection-string"
  value        = azurerm_redis_cache.main.primary_connection_string
  key_vault_id = azurerm_key_vault.main.id
}

resource "azurerm_key_vault_secret" "db_connection_string" {
  name         = "db-connection-string"
  value        = local.db_connection_string
  key_vault_id = azurerm_key_vault.main.id
}

resource "azurerm_key_vault_secret" "marketing_api_base_url" {
  name         = "marketing-api-base-url"
  value        = var.api_base_url
  key_vault_id = azurerm_key_vault.main.id
}
