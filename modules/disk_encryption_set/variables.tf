variable "disk_encryption_set_name" {
  type        = string
  description = "The name of the Disk Encryption Set"
}

variable "resource_group_name" {
  type        = string
  description = "The name of the resource group"
}

variable "location" {
  type        = string
  description = "The Azure location where resources will be created"
}

variable "key_vault_key_id" {
  type        = string
  description = "The ID of the Key Vault Key to use for disk encryption"
}

variable "key_vault_id" {
  type        = string
  description = "The ID of the Key Vault"
}

variable "tags" {
  type        = map(string)
  description = "Tags to associate with resources"
  default     = {}
}