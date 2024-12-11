output "disk_encryption_set_id" {
  description = "The ID of the Disk Encryption Set"
  value       = azurerm_disk_encryption_set.DEJOMSIL5DSKES.id
}

output "disk_encryption_set_identity" {
  description = "The identity of the Disk Encryption Set"
  value       = azurerm_disk_encryption_set.DEJOMSIL5DSKES.identity[0]
}
