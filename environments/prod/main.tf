resource "random_string" "suffix" {
  length  = 6
  upper   = false
  special = false
}

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

module "network" {
  source = "../../modules/network"

  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  name_prefix         = var.name_prefix
  common_tags         = var.common_tags
}

module "compute" {
  source = "../../modules/compute"

  resource_group_name    = azurerm_resource_group.main.name
  location               = azurerm_resource_group.main.location
  name_prefix            = var.name_prefix
  unique_suffix          = local.unique_suffix
  aks_nodes_subnet_id    = module.network.aks_nodes_subnet_id
  aks_node_count         = var.aks_node_count
  aks_node_vm_size       = var.aks_node_vm_size
  aks_dns_prefix         = var.aks_dns_prefix
  aks_kubernetes_version = var.aks_kubernetes_version
  common_tags            = var.common_tags
}

module "data" {
  source = "../../modules/data"

  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  name_prefix         = var.name_prefix
  unique_suffix       = local.unique_suffix
  sql_admin_username  = var.sql_admin_username
  sql_admin_password  = random_password.sql_admin_password.result
  api_base_url        = var.api_base_url
  common_tags         = var.common_tags
}

data "azurerm_client_config" "current" {}

resource "azurerm_key_vault_access_policy" "csi_driver" {
  key_vault_id = module.data.key_vault_id
  tenant_id    = data.azurerm_client_config.current.tenant_id
  object_id    = module.compute.key_vault_secrets_provider_object_id

  secret_permissions = ["Get", "List"]
}
