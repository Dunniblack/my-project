resource "azurerm_key_vault" "default" {
  name                = module.name-map.key_vault_name
  location            = var.location
  resource_group_name = azurerm_resource_group.default.name
  tenant_id           = module.resources.azure_config.tenant_id
  sku_name            = "premium"  # Premium SKU for HSM (Hardware Security Modules) and advanced features

  # NIST 800-53: Protect against accidental deletion
  purge_protection_enabled = (
    contains(["test", "prod"], var.stage) ?
    true :
    false
  )

  # NIST 800-53: Encryption at Rest using Azure Managed Keys
  enabled_for_disk_encryption = true

  # Allow Azure compute resource fetch secrets frm KV during deployment
  enabled_for_deployment     = true

  enable_rbac_authorization  = false               # NIST 800-53: Use RBAC for access control
  
   # Secure network access using private endpoints (Optional)
  public_network_access_enabled = false           # NIST 800-53: Disable public network access
  
  network_acls {
    bypass                     = "AzureServices"
    default_action             = "Allow"
    virtual_network_subnet_ids = [
      module.resources.subnet.id,
      module.resources.cmnsvc_subnet.id
    ]
  }

  lifecycle {
    ignore_changes = [
      purge_protection_enabled
    ]
  }
}

resource "azurerm_private_endpoint" "keyvault_default" {
  name                = "keyvault-default-private-endpoint"
  location            = var.location
  resource_group_name = module.name-map.global_resource_group_name
  subnet_id           = module.resources.subnet.id

  private_service_connection {
    name                           = "keyvault-default-service-connection"
    private_connection_resource_id = azurerm_key_vault.default.id
    is_manual_connection           = false
    subresource_names              = ["vault"]
  }
}

data "azurerm_private_dns_zone" "keyvault" {
  name                = "privatelink.vaultcore.azure.net"
  resource_group_name = module.name-map.global_resource_group_name
}

resource "azurerm_private_dns_a_record" "keyvault" {
  name                = lower(module.name-map.key_vault_name)
  zone_name           = data.azurerm_private_dns_zone.keyvault.name
  resource_group_name = module.name-map.global_resource_group_name
  ttl                 = 300
  records             = [
    azurerm_private_endpoint.keyvault_default.private_service_connection[0].private_ip_address
  ]
}

# NIST 800-53: Diagnostic settings for audit logs
resource "azurerm_monitor_diagnostic_setting" "keyvault" {
  name                       = "keyvault-diagnostics"
  target_resource_id         = azurerm_key_vault.default.id
  log_analytics_workspace_id = module.resources.c1_log_analytics_workspace.id

  # Enable logging for the AuditEvent category
  enabled_log {
    category = "AuditEvent"
  }

  # Enable metrics for AllMetrics category
  metric {
    category = "AllMetrics"
  }
}

resource "azurerm_key_vault_access_policy" "service_principal" {
  key_vault_id = azurerm_key_vault.default.id

  tenant_id = module.resources.azure_config.tenant_id
  object_id = module.resources.azure_config.object_id

  key_permissions = [
    "Create",
    "Delete",
    "Get",
    "Purge",
    "Recover",
    "Update",
    "List",
    "Decrypt",
    "Sign",
    "GetRotationPolicy",
    "SetRotationPolicy",
    "WrapKey",
    "UnwrapKey",
  ]
}
