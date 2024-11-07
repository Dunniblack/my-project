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
