terraform {
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.11.0"
    }
  }
  backend "azurerm" {
    access_key = "{{ ARM_ACCESS_KEY }}"
  }
}

provider "azurerm" {
  subscription_id     = var.subscription_id
  storage_use_azuread = true
  features {}
}

data "terraform_remote_state" "az" {
  backend = "azurerm"
  config = {
    resource_group_name  = var.tfstate_resource_group
    storage_account_name = var.tfstate_storage_account
    container_name       = var.tfstate_container
    key                  = var.tfstate_key
    access_key           = "{{ ARM_ACCESS_KEY }}"
  }
}

module "name-map" {
  source = "../modules/name-map"

  environment_name = var.environment_name
  parent_module    = var.parent_module
  stage            = var.stage
  project          = var.project
  c1_project       = var.c1_project
  functional_area  = var.functional_area
  location         = var.location
}

module "resources" {
  source = "../modules/resources"

  resource_group_name          = var.resource_group_name
  vnet_name                    = var.vnet_name
  subnet_name                  = var.subnet_name

  cmnsvc_resource_group_name   = var.cmnsvc_resource_group_name
  cmnsvc_vnet_name             = var.cmnsvc_vnet_name
  cmnsvc_subnet_name           = var.cmnsvc_subnet_name

  core_key_vault_name          = var.core_key_vault_name
  kv_resource_group_name       = var.kv_resource_group_name

  log_analytics_workspace_name = var.log_analytics_workspace_name
  la_resource_group_name       = var.la_resource_group_name
}
