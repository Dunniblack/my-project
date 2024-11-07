terraform {
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "4.3.0"
    }
  }
  backend "azurerm" {
    access_key = "{{ ARM_ACCESS_KEY }}"
  }
}

provider "azurerm" {
  subscription_id = var.subscription_id
  features {}
}

module "name-map" {
  source = "../modules/name-map"

  environment_name = var.environment_name
  stage            = var.stage
  project          = var.project
  functional_area  = var.functional_area
  location         = var.location
}

module "resources" {
  source = "../modules/resources"

  resource_group_name          = var.resource_group_name
  vnet_name                    = var.vnet_name
  subnet_name                  = var.subnet_name
  core_resource_group_name     = var.core_resource_group_name
  log_analytics_workspace_name = var.log_analytics_workspace_name
}


module "nist_compliant_keyvault" {
  source = "../modules/keyvault"

  key_vault_name             = module.name-map.key_vault_name
  resource_group_name        = var.resource_group_name
  location                   = var.location
  tenant_id                  = var.tenant_id
  vnet_name                  = var.vnet_name
  subnet_name                = var.subnet_name
  log_analytics_workspace_id = module.resources.log_analytics_workspace.id
  subnet_id                  = module.resources.subnet.id
}
