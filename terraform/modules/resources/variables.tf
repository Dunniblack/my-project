variable "resource_group_name" {
  type        = string
  description = "The name of the AKS Resource Group."
}

variable "vnet_name" {
  type        = string
  description = "The Virtual Network Name."
}

variable "subnet_name" {
  type        = string
  description = "The Subnet Name."
}

variable "core_resource_group_name" {
  type        = string
  description = "The name of the Core Resource Group."
}

variable "log_analytics_workspace_name" {
  type        = string
  description = "The Log Analytics Workspace Name."
}
