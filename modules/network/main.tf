resource "azurerm_virtual_network" "main" {
  name                = "${var.name_prefix}-vnet"
  location            = var.location
  resource_group_name = var.resource_group_name
  address_space       = ["10.20.0.0/16"]
  tags                = var.common_tags
}

resource "azurerm_subnet" "aks_nodes" {
  name                 = "aks-nodes-subnet"
  resource_group_name  = var.resource_group_name
  virtual_network_name = azurerm_virtual_network.main.name
  address_prefixes     = ["10.20.0.0/23"]

  depends_on = [azurerm_virtual_network.main]
}

resource "azurerm_subnet" "private_endpoints" {
  name                              = "private-endpoints-subnet"
  resource_group_name               = var.resource_group_name
  virtual_network_name              = azurerm_virtual_network.main.name
  address_prefixes                  = ["10.20.2.0/24"]
  private_endpoint_network_policies = "Disabled"

  depends_on = [azurerm_virtual_network.main]
}
