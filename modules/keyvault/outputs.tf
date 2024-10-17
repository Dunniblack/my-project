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

# Output private endpoint connection ID (if private endpoint is used)
output "private_endpoint_id" {
  description = "The ID of the private endpoint associated with the Key Vault, if network isolation is enabled."
  value       = length(azurerm_private_endpoint.keyvault_private_endpoint) > 0 ? azurerm_private_endpoint.keyvault_private_endpoint.id : null
}

# Output private IP address for the Key Vault (if private endpoint is used)
output "private_endpoint_ip" {
  description = "The private IP address assigned to the Key Vault through the private endpoint."
  value       = length(azurerm_private_endpoint.keyvault_private_endpoint.private_service_connection) > 0 ? azurerm_private_endpoint.keyvault_private_endpoint.private_service_connection[0].private_ip_address : null
}

output "key_vault_key_id" {
  description = "The ID of the Key Vault Key used for disk encryption"
  value       = azurerm_key_vault_key.disk_encryption_key.id
}
