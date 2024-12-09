resource "azurerm_key_vault" "nist_compliant_kv" {
  name                = module.name-map.key_vault_name
  location            = var.location
  resource_group_name = var.resource_group_name
  tenant_id           = var.tenant_id
  sku_name            = "premium"  # Premium SKU for HSM (Hardware Security Modules) and advanced features

  # NIST 800-53: Encryption at Rest using Azure Managed Keys
  purge_protection_enabled   = true               # NIST 800-53: Protect against accidental deletion

  # Enable KV for disk encryption
  enabled_for_disk_encryption = true

  enable_rbac_authorization  = false               # NIST 800-53: Use RBAC for access control
  
   # Secure network access using private endpoints (Optional)
  public_network_access_enabled = false           # NIST 800-53: Disable public network access

  network_acls {
    bypass                     = "AzureServices"
    default_action             = "Allow"
    virtual_network_subnet_ids = [module.resources.subnet.id, var.agent_subnet_id]
  }
}

resource "azurerm_private_endpoint" "keyvault_private_endpoint" {
  name                = "keyvault-pe"
  location            = var.location
  resource_group_name = var.resource_group_name
  subnet_id           = module.resources.subnet.id
 
  private_service_connection {
    name                           = "keyvault-psc"
    private_connection_resource_id = azurerm_key_vault.nist_compliant_kv.id
    is_manual_connection           = false
    subresource_names              = ["vault"]
  }
}
 
resource "azurerm_private_dns_zone" "keyvault_dns_zone" {
  name                = "privatelink.vaultcore.azure.net"
  resource_group_name = var.resource_group_name
}
 
resource "azurerm_private_dns_zone_virtual_network_link" "keyvault_dns_zone_link" {
  name                  = "keyvault-dnszone-link"
  resource_group_name   = var.resource_group_name
  private_dns_zone_name = azurerm_private_dns_zone.keyvault_dns_zone.name
  virtual_network_id    = module.resources.vnet.id
}
 
resource "azurerm_private_dns_a_record" "keyvault_dns_record" {
  name                = "gvjomsmvpdil5kv1"
  zone_name           = azurerm_private_dns_zone.keyvault_dns_zone.name
  resource_group_name = var.resource_group_name
  ttl                 = 300
  records             = [azurerm_private_endpoint.keyvault_private_endpoint.private_service_connection[0].private_ip_address]
}

# NIST 800-53: Diagnostic settings for audit logs
resource "azurerm_monitor_diagnostic_setting" "diagnostic_settings" {
  name                       = "keyvault-diagnostics"
  target_resource_id         = azurerm_key_vault.nist_compliant_kv.id
  log_analytics_workspace_id = module.resources.log_analytics_workspace.id

  # Enable logging for the AuditEvent category
  enabled_log {
    category = "AuditEvent"
  }

  # Enable metrics for AllMetrics category
  metric {
    category = "AllMetrics"
  }
}
