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
  features {}
}

module "invoke_runbook" {
  source = "../modules/invoke-runbook"
  
  automation_account_name = "agadoriancitizen"
  resource_group_name    = var.resource_group_name
  environment_name       = var.environment_name
  
  acr_private_endpoint_id = module.container_registry.private_endpoint_id
  acr_private_dns_link_id = module.container_registry.private_dns_link_id
}