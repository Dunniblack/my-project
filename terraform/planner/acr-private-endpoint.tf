data "azurerm_container_registry" "acr" {
  count               = 1
  name                = module.name-map.container_registry_name
  resource_group_name = module.name-map.global_resource_group_name
}

resource "azurerm_private_endpoint" "acr" {
  count               = 1
  name                = "${module.name-map.container_registry_name}-private-endpoint"
  resource_group_name = module.name-map.global_resource_group_name
  location            = var.location
  subnet_id           = module.resources.subnet.id
  
  private_service_connection {
    name                           = "${module.name-map.container_registry_name}-service-connection"
    private_connection_resource_id = data.azurerm_container_registry.acr.0.id
    is_manual_connection           = false
    subresource_names = [
      "registry"
    ]
  }
}

data "azurerm_private_dns_zone" "acr" {
  count               = 1
  name                = "privatelink.azurecr.us"
  resource_group_name = module.name-map.global_resource_group_name
}

resource "azurerm_private_dns_a_record" "acr" {
  count               = 1
  name                = lower(module.name-map.container_registry_name)
  zone_name           = data.azurerm_private_dns_zone.acr.0.name
  resource_group_name = module.name-map.global_resource_group_name
  ttl                 = 300
  records             = [
    try(azurerm_private_endpoint.acr.0.private_service_connection.0.private_ip_address, "")
  ]
}
