odules/keyvault/main.tf
resource "azurerm_key_vault" "nist_compliant_kv" {
  name                = var.key_vault_name
  location            = var.location
  resource_group_name = var.resource_group_name
  tenant_id           = var.tenant_id
  sku_name            = "premium"  # Premium SKU for HSM (Hardware Security Modules) and advanced features

  # NIST 800-53: Encryption at Rest using Azure Managed Keys
  purge_protection_enabled   = true               # NIST 800-53: Protect against accidental deletion
  enable_rbac_authorization  = true               # NIST 800-53: Use RBAC for access control
  
  # Secure network access using private endpoints (Optional)
  public_network_access_enabled = false           # NIST 800-53: Disable public network access
}

# NIST 800-53: Diagnostic settings for audit logs
resource "azurerm_monitor_diagnostic_setting" "diagnostic_settings" {
  name                      = "keyvault-diagnostics"
  target_resource_id        = azurerm_key_vault.nist_compliant_kv.id
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

resource "azurerm_virtual_network" "vnet" {
  name                = "AZ-GV-DOD-AF-CCE-AFMC-D-IL5-JOMSMVP-VNT-01"
  location            = var.location
  resource_group_name = var.resource_group_name
  address_space       = ["10.130.0.0/20"]

  lifecycle {
    prevent_destroy = true  # Prevent Terraform from attempting to destroy this resource
  }
}
