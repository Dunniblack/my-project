output "resource_group" {
  description = "AKS Resource Group"
  value       = data.azurerm_resource_group.aks
}

output "core_resource_group" {
  description = "Core Resource Group"
  value       = data.azurerm_resource_group.core
}

output "vnet" {
  description = "Virtual Network"
  value       = data.azurerm_virtual_network.default
}

output "subnet" {
  description = "Subnet"
  value       = data.azurerm_subnet.default
}

output "log_analytics_workspace" {
  description = "Log Analytics Workspace"
  value       = data.azurerm_log_analytics_workspace.default
}
