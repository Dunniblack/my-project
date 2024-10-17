output "disk_encryption_set_id" {
  description = "The ID of the Disk Encryption Set"
  value       = azurerm_disk_encryption_set.des.id
}

output "disk_encryption_set_identity" {
  description = "The identity of the Disk Encryption Set"
  value       = azurerm_disk_encryption_set.des.identity[0]
}