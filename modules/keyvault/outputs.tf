# Output the Key Vault ID
output "key_vault_id" {
  description = "The ID of the NIST 800-53 compliant Azure Key Vault."
  value       = azurerm_key_vault.nist_compliant_kv.id
}

# Output the Key Vault URI
output "key_vault_uri" {
  description = "The URI of the Azure Key Vault used for accessing secrets, keys, and certificates."
  value       = azurerm_key_vault.nist_compliant_kv.vault_uri
}

# Output the Key Vault Tenant ID (Optional)
output "tenant_id" {
  description = "The Azure Active Directory Tenant ID associated with the Key Vault."
  value       = azurerm_key_vault.nist_compliant_kv.tenant_id
}

output "key_vault_key_id" {
  description = "The ID of the Key Vault Key used for disk encryption"
  value       = azurerm_key_vault_key.disk_encryption_key.id
}
