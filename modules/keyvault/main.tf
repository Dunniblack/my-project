# modules/keyvault/main.tf

data "azurerm_client_config" "current" {}

data "azurerm_virtual_network" "vnet" {
  name = var.vnet_name
  resource_group_name = var.resource_group_name
}

data "azurerm_subnet" "subnet" {
  name                 = var.subnet_name
  virtual_network_name = var.vnet_name
  resource_group_name  = var.resource_group_name
}

resource "azurerm_key_vault" "nist_compliant_kv" {
  name                = var.key_vault_name
  location            = var.location
  resource_group_name = var.resource_group_name
  tenant_id           = var.tenant_id
  sku_name            = "premium"  # Premium SKU for HSM (Hardware Security Modules) and advanced features

  # NIST 800-53: Encryption at Rest using Azure Managed Keys
  purge_protection_enabled   = true               # NIST 800-53: Protect against accidental deletion

  # Enable KV for disk encryption
  enabled_for_disk_encryption = true

  # FIXME - Disabling RBAC to allow Key Vault Access Policy - need to change below to 'true' if possible
  enable_rbac_authorization  = false               # NIST 800-53: Use RBAC for access control
  
   # Secure network access using private endpoints (Optional)
  public_network_access_enabled = false           # NIST 800-53: Disable public network access
  
  network_acls {
    bypass                     = "AzureServices"
    default_action             = "Allow"
    virtual_network_subnet_ids = [data.azurerm_subnet.subnet.id]
  }

}

# NIST 800-53: Diagnostic settings for audit logs
resource "azurerm_monitor_diagnostic_setting" "diagnostic_settings" {
  name                       = "keyvault-diagnostics"
  target_resource_id         = azurerm_key_vault.nist_compliant_kv.id
  log_analytics_workspace_id = var.log_analytics_workspace_id  # Ensure this is correctly defined

  # Enable logging for the AuditEvent category
  enabled_log {
    category = "AuditEvent"
  }

  # Enable metrics for AllMetrics category
  metric {
    category = "AllMetrics"
  }
}
