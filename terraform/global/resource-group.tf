resource "azurerm_resource_group" "global" {
  name     = module.name-map.global_resource_group_name
  location = var.location
}