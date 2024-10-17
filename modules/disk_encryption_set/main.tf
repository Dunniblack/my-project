resource "azurerm_disk_encryption_set" "DEJOMSIL5DSKES" {
  name                = var.disk_encryption_set_name
  resource_group_name = var.resource_group_name
  location            = var.location
  key_vault_key_id    = var.key_vault_key_id

  identity {
    type = "SystemAssigned"
  }
}

# Grant the Disk Encryption Set access to the Key Vault
resource "azurerm_role_assignment" "DEJOMIL5DSKESKVCU" {
  scope                = var.key_vault_id
  role_definition_name = "Key Vault Crypto Service Encryption User"
  principal_id         = azurerm_disk_encryption_set.des.identity[0].principal_id
}