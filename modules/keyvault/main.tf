resource "azurerm_key_vault" "nist_compliant_kv" {
  name                        = var.key_vault_name
  resource_group_name         = var.resource_group_name
  tenant_id                   = var.tenant_id
  sku_name                    = "premium" # Premium SKU for HSM (Hardware Security Modules) and advanced features

  purge_protection_enabled    = true      # NIST 800-53: Protect against accidental deletion
  enable_rbac_authorization   = true      # NIST 800-53: Use RBAC for access control
  public_network_access_enabled = false   # NIST 800-53: Disable public network access
  location                    = var.location
}

# Diagnostic settings for audit logs
resource "azurerm_monitor_diagnostic_setting" "diagnostic_settings" {
  name                       = "keyvault-diagnostics"
  target_resource_id        = azurerm_key_vault.nist_compliant_kv.id
  log_analytics_workspace_id = var.log_analytics_workspace_id

  enabled_log {
    category = "AuditEvent"
  }

  metric {
    category = "AllMetrics"
  }
}

# Optionally, configure private endpoints for network isolation
resource "azurerm_private_endpoint" "keyvault_private_endpoint" {
  name                 = "keyvault-private-endpoint"
  location             = azurerm_key_vault.nist_compliant_kv.location
  resource_group_name  = azurerm_key_vault.nist_compliant_kv.resource_group_name
  subnet_id            = var.subnet_id

  private_service_connection {
    name                           = "keyvault-connection"
    private_connection_resource_id = azurerm_key_vault.nist_compliant_kv.id
    is_manual_connection           = false
    subresource_names              = ["vault"]
  }
}

# Creates a key for the Disk Encryption Set.
resource "azurerm_key_vault_key" "disk_encryption_key" {
  name         = "disk-encryption-key"
  key_vault_id = azurerm_key_vault.nist_compliant_kv.id
  key_type     = "RSA"
  key_size     = 2048

  key_opts = [
    "decrypt",
    "encrypt",
    "sign",
    "unwrapKey",
    "verify",
    "wrapKey",
  ]
}
