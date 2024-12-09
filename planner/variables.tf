# Variables for Azure resources

variable "environment_name" {
  description = "The name of the Environment"
  type        = string
}

variable "stage" {
  description = "The stage of the Environment (dev, test, prod)"
  type        = string
}

variable "project" {
  description = "The Project Name"
  type        = string
  default     = "JOMS"
}

variable "functional_area" {
  description = "The Functional Area of the environment (AFMC)"
  type        = string
  default     = "AFMC"
}

variable "location" {
  description = "The Azure location where resources will be created."
  type        = string
  default     = "USGov Virginia"
}

variable "tenant_id" {
  type        = string
  description = "Azure Active Directory tenant ID."
}

variable "subscription_id" {
  description = "The Subscription ID for Azure."
  type        = string
}

variable "resource_group_name" {
  description = "The name of the Resource Group."
  type        = string
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
