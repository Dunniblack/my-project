# Variables for the Key Vault
variable "key_vault_name" {
  type        = string
  description = "The name of the Key Vault."
}

variable "resource_group_name" {
  type        = string
  description = "The resource group in which to create the Key Vault."
}

variable "location" {
  type        = string
  description = "The location where the Key Vault will be created."
}

variable "tenant_id" {
  type        = string
  description = "Azure Active Directory tenant ID."
}

variable "log_analytics_workspace_id" {
  type        = string
  description = "Log Analytics Workspace ID for diagnostics and auditing."
}

variable "subnet_id" {
  type        = string
  description = "The ID of the subnet for the private endpoint."
}
