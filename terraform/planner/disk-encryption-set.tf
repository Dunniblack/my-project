resource "azurerm_key_vault_key" "disk_encryption_set" {
  name         = module.name-map.disk_encryption_set_key_name
  key_vault_id = azurerm_key_vault.default.id
  key_type     = "RSA"
  key_size     = 2048

  rotation_policy {
    automatic {
      time_before_expiry = "P30D"
    }

    expire_after         = "P90D"
    notify_before_expiry = "P29D"
  }

  key_opts = [
    "decrypt",
    "encrypt",
    "sign",
    "unwrapKey",
    "verify",
    "wrapKey",
  ]

  depends_on = [
    azurerm_key_vault_access_policy.service_principal,
  ]
}

resource "azurerm_disk_encryption_set" "default" {
  name                      = module.name-map.disk_encryption_set_name
  resource_group_name       = azurerm_resource_group.default.name
  location                  = var.location
  key_vault_key_id          = azurerm_key_vault_key.disk_encryption_set.versionless_id
  auto_key_rotation_enabled = true

  identity {
    type = "SystemAssigned"
  }
}

resource "azurerm_key_vault_access_policy" "disk-encryption-access" {
  key_vault_id = azurerm_key_vault.default.id

  tenant_id = azurerm_disk_encryption_set.default.identity[0].tenant_id
  object_id = azurerm_disk_encryption_set.default.identity[0].principal_id

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
    "UnwrapKey",
    "WrapKey",
  ]

  # TODO:FIXME - Depends on Private Endpoint / Internal networking
}
