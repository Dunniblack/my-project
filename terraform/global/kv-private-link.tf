
resource "azurerm_private_dns_zone" "keyvault" {
  name                = "privatelink.vaultcore.azure.net"
  resource_group_name = azurerm_resource_group.global.name
}

resource "azurerm_private_dns_zone_virtual_network_link" "keyvault_link_default" {
  name                  = "keyvault-link-default"
  resource_group_name   = azurerm_resource_group.global.name
  private_dns_zone_name = azurerm_private_dns_zone.keyvault.name
  virtual_network_id    = module.resources.vnet.id
  registration_enabled  = false
}
