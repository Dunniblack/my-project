output "azure_config" {
  description = "The current Azure Client Config"
  value       = data.azurerm_client_config.current
}

output "resource_group" {
  description = "AKS Resource Group"
  value       = data.azurerm_resource_group.aks
}

output "vnet" {
  description = "AKS Virtual Network"
  value       = data.azurerm_virtual_network.aks
}

output "subnet" {
  description = "AKS Subnet"
  value       = data.azurerm_subnet.aks
}

output "cmnsvc_vnet" {
  description = "C1 Common Service Virtual Network"
  value       = data.azurerm_virtual_network.cmnsvc
}

output "cmnsvc_subnet" {
  description = "C1 Common Service Subnet"
  value       = data.azurerm_subnet.cmnsvc
}

output "c1_key_vault" {
  description = "C1 Key Vault"
  value       = data.azurerm_key_vault.c1
}

output "c1_log_analytics_workspace" {
  description = "C1 Log Analytics Workspace"
  value       = data.azurerm_log_analytics_workspace.c1
}
