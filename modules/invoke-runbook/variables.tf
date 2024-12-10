variable "automation_account_name" {
 type = string
}

variable "resource_group_name" {
 type = string
}

variable "environment_name" {
 type = string
}

variable "runbook_name" {
  type = string
  default = "update-bastion-hosts-file"
}

variable "acr_private_endpoint_id" {
 type = string
 default = null
}

variable "acr_private_dns_link_id" {
 type = string
 default = null
}

variable "kv_private_endpoint_id" {
 type = string
 default = null
}

variable "kv_private_dns_link_id" {
 type = string
 default = null
}

variable "disk_encryption_set_id" {
 type = string
 default = null
}

variable "aks_cluster_id" {
 type = string
 default = null
}

