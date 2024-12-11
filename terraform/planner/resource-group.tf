resource "azurerm_resource_group" "default" {
  name     = module.name-map.resource_group_name
  location = var.location
}
