resource "azurerm_disk_encryption_set" "disk_encryption_set" {
  name                = var.disk_encryption_set_name
  resource_group_name = var.resource_group_name
  location            = var.location
  key_vault_key_id    = var.key_vault_key_id

  identity {
    type = "SystemAssigned"
  }
}

resource "azurerm_key_vault" "disk_encryption_kv" {
  name                        = "des-keyvault"
  location                    = var.location
  resource_group_name         = var.resource_group_name
  tenant_id                   = data.azurerm_client_config.current.tenant_id
  sku_name                    = "premium"
  enabled_for_disk_encryption = true
  purge_protection_enabled    = true
}

resource "azurerm_key_vault_access_policy" "disk-encryption-access" {
  key_vault_id = azurerm_key_vault.disk_encryption_kv.id

  tenant_id = azurerm_disk_encryption_set.disk_encryption_set.identity[0].tenant_id
  object_id = azurerm_disk_encryption_set.disk_encryption_set.identity[0].principal_id

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
  ]
}

resource "azurerm_key_vault_access_policy" "user-access" {
  key_vault_id = azurerm_key_vault.disk_encryption_kv.id

  tenant_id = data.azurerm_client_config.current.tenant_id
  object_id = data.azurerm_client_config.current.object_id

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
  ]
}

# Grant the Disk Encryption Set access to the Key Vault
resource "azurerm_role_assignment" "DEJOMIL5DSKESKVCU" {
  scope                = azurerm_key_vault.disk_encryption_kv.id
  role_definition_name = "Key Vault Crypto Service Encryption User"
  principal_id         = azurerm_disk_encryption_set.disk_encryption_set.identity[0].principal_id
}
