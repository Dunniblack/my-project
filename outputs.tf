# output "storage_account_name" {
#   value = azurerm_storage_account.example.name
# }

# output "container_name" {
#   value = azurerm_storage_container.example.name
# }

output "disk_encryption_set_id" {
  description = "The ID of the Disk Encryption Set"
  value       = module.disk_encryption_set.disk_encryption_set_id
}

output "disk_encryption_set_identity" {
  description = "The identity of the Disk Encryption Set"
  value       = module.disk_encryption_set.disk_encryption_set_identity
}