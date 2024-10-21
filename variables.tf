# Variables for Azure resources
variable "resource_group_name" {
  description = "The name of the resource group"
  type        = string
}

variable "location" {
  description = "The Azure location where resources will be created."
  type        = string
}

variable "storage_account_name" {
  description = "The name of the storage account"
  type        = string
  validation {
    condition     = length(var.storage_account_name) >= 3 && length(var.storage_account_name) <= 24 && can(regex("^[a-z0-9]{3,24}$", var.storage_account_name))
    error_message = "The storage account name must be between 3 and 24 characters long and use only lowercase letters and numbers."
  }
}

variable "container_name" {
  description = "The name of the Storage Container."
  type        = string
}

variable "subscription_id" {
  description = "The Subscription ID for Azure"
  type        = string
}

variable "log_analytics_workspace_id" {
  description = "ID of the Log Analytics workspace"
  type        = string
}

variable "admin_object_id" {
  description = "Object ID for admin user"
  type        = string
}

variable "tenant_id" {
  type        = string
  description = "The tenant ID for your Azure account"
}

variable "key_vault_name" {
  type        = string
  description = "The name of the Key Vault."
}

variable "tags" {
  type        = map(string)
  description = "Tags to associate with resources"
  default     = {}
}

variable "arm_access_key" {
  type        = string
  description = "Access key for storage account"
  sensitive   = true
}

variable "disk_encryption_set_name" {
  type        = string
  description = "The name of the Disk Encryption Set"
}
