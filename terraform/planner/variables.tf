# Variables for Azure resources

variable "environment_name" {
  description = "The name of the Environment"
  type        = string
}

variable "parent_module" {
  description = "The name of the Parent Terraform Module."
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

variable "c1_project" {
  description = "The C1 Project Name"
  type        = string
  default     = "JOMSMVP"
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

variable "subscription_id" {
  description = "The Subscription ID for Azure."
  type        = string
}

variable "resource_group_name" {
  description = "The name of the Resource Group."
  type        = string
}

variable "tfstate_resource_group" {
  description = "The name of the TF State Resource Group."
  type        = string
}

variable "tfstate_storage_account" {
  description = "The name of the TF State Storage Account."
  type        = string
}

variable "tfstate_container" {
  description = "The name of the TF State Container."
  type        = string
}

variable "tfstate_key" {
  description = "The name of the TF State Key."
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
  description = "The Subnet Name of the C1 Common Services"
}

variable "cmnsvc_location" {
  type        = string
  description = "The Location of the C1 Common Services"
  default     = "USDoD East"
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
  description = "The C1 Log Analytics Workspace Name."
}

variable "la_resource_group_name" {
  type        = string
  description = "The name of the C1 Log Analytics Workspace Resource Group."
}

variable "automation_account_name" {
  type        = string
  description = "The C1 Automation Account Name."
}

variable "aa_resource_group_name" {
  type        = string
  description = "The name of the C1 Automation Account Resource Group."
}

variable "gcds_ips" {
  type        = string
  description = "Comma separated list of GCDS IPs."
}

variable "admin_aad_group_id" {
  description = "The Azure Active Directory Group ID of Admin Users."
  type        = string
}

variable "read_only_aad_group_id" {
  description = "The Azure Active Directory Group ID of Read Only Users."
  type        = string
  default     = null
}

variable "kubernetes_version" {
  description = "The version of the Azure Kubernetes Service Resource."
  type        = string
  default     = null
}