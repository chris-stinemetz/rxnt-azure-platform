resource "random_password" "sql_admin_password" {
  length           = 24
  special          = true
  override_special = "_%@"
}

resource "azurerm_resource_group" "main" {
  name     = var.resource_group_name
  location = var.location
  tags     = var.common_tags
}

module "data" {
  source = "../../modules/data"

  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  name_prefix         = var.name_prefix
  unique_suffix       = local.unique_suffix
  sql_admin_username  = var.sql_admin_username
  sql_admin_password  = random_password.sql_admin_password.result
  common_tags         = var.common_tags
}

module "compute" {
  source = "../../modules/compute"

  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  name_prefix         = var.name_prefix
  unique_suffix       = local.unique_suffix
  key_vault_name      = module.data.key_vault_name
  app_service_sku     = var.app_service_sku
  common_tags         = var.common_tags
}

data "azurerm_client_config" "current" {}

resource "azurerm_key_vault_access_policy" "api" {
  key_vault_id = module.data.key_vault_id
  tenant_id    = data.azurerm_client_config.current.tenant_id
  object_id    = module.compute.api_principal_id

  secret_permissions = ["Get", "List"]
}

resource "azurerm_key_vault_access_policy" "site" {
  key_vault_id = module.data.key_vault_id
  tenant_id    = data.azurerm_client_config.current.tenant_id
  object_id    = module.compute.site_principal_id

  secret_permissions = ["Get", "List"]
}
