# Make sure the current Service Prinicipal has access to add Keys to the KV
resource "azurerm_key_vault_access_policy" "service_principal" {
  count        = 0
  key_vault_id = module.resources.c1_key_vault.id
  tenant_id    = module.resources.azure_config.tenant_id
  object_id    = module.resources.azure_config.object_id

  secret_permissions = [
    "Backup", 
    "Delete", 
    "Get", 
    "List", 
    "Purge", 
    "Recover", 
    "Restore",
    "Set"
  ]

  key_permissions = [
    "Backup",
    "Create",
    "Decrypt",
    "Delete",
    "Encrypt",
    "Get",
    "Import",
    "List",
    "Purge",
    "Recover",
    "Restore",
    "Sign",
    "UnwrapKey",
    "Update",
    "Verify",
    "WrapKey",
    "Release",
    "Rotate",
    "GetRotationPolicy",
    "SetRotationPolicy"
  ]
}
