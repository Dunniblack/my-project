variable "resource_group_name" {
  type        = string
  description = "The name of the AKS Resource Group."
}

variable "vnet_name" {
  type        = string
  description = "The Virtual Network Name of the AKS Resources."
}

variable "subnet_name" {
  type        = string
  description = "The Subnet Name of the AKS Resources."
}

variable "cmnsvc_resource_group_name" {
  description = "The name of the Resource Group of the C1 Common Services."
  type        = string
}

variable "cmnsvc_vnet_name" {
  type        = string
  description = "The Virtual Network Name of the C1 Common Services."
}

variable "cmnsvc_subnet_name" {
  type        = string
  description = "The Subnet Nameo f the C1 Common Services"
}

variable "core_key_vault_name" {
  type        = string
  description = "The C1 Key Vault Name."
}

variable "kv_resource_group_name" {
  type        = string
  description = "The name of the C1 Key Vault Resource Group."
}

variable "log_analytics_workspace_name" {
  type        = string
  description = "The Log Analytics Workspace Name."
}

variable "la_resource_group_name" {
  type        = string
  description = "The name of the C1 Log Analytics Workspace Resource Group."
}
