data "azurerm_client_config" "current" {}

data "azurerm_resource_group" "aks" {
  name = var.resource_group_name
}

data "azurerm_virtual_network" "aks" {
  name                = var.vnet_name
  resource_group_name = var.resource_group_name
}

data "azurerm_subnet" "aks" {
  name                 = var.subnet_name
  virtual_network_name = var.vnet_name
  resource_group_name  = var.resource_group_name
}

data "azurerm_virtual_network" "cmnsvc" {
  name                = var.cmnsvc_vnet_name
  resource_group_name = var.cmnsvc_resource_group_name
}

data "azurerm_subnet" "cmnsvc" {
  name                 = var.cmnsvc_subnet_name
  virtual_network_name = var.cmnsvc_vnet_name
  resource_group_name  = var.cmnsvc_resource_group_name
}

data "azurerm_key_vault" "c1" {
  name                = var.core_key_vault_name
  resource_group_name = var.kv_resource_group_name
}

data "azurerm_log_analytics_workspace" "c1" {
  name                = var.log_analytics_workspace_name
  resource_group_name = var.la_resource_group_name
}
