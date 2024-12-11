output "c1_project_name" {
  description = "The Project Name that C1 uses to provision resources."
  value       = local.c1_project_name
}

output "container_registry_name" {
  description = "The Name of the Azure Container Registry to create."
  value       = local.container_registry_name
}

output "key_vault_name" {
  description = "The Name of the Key Vault to create."
  value       = local.key_vault_name
}

output "sadus_storage_account_name" {
  description = "The Name of the Sadus Storage Account."
  value       = local.sadus_storage_account_name
}

output "disk_encryption_set_name" {
  description = "The name of the disk encryption set"
  value       = local.disk_encryption_set_name
}

output "disk_encryption_set_key_name" {
  description = "The name of the disk encryption set keyvault key"
  value       = local.disk_encryption_set_key_name
}

output "resource_group_name" {
  description = "The name of the resource group for resources to be deployed"
  value       = local.resource_group_name
}

output "global_resource_group_name" {
  description = "The name of the GLobal resource group"
  value       = local.global_resource_group_name
}

output "aks_name" {
  description = "The Name of the Azure Kuberenetes Service Resource."
  value       = local.aks_name
}
