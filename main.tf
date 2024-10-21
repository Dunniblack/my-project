terraform {
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "4.3.0"
    }
  }
}

provider "azurerm" {
  features {}
}

# Call the Key Vault module
module "nist_compliant_keyvault" {
  source = "./modules/keyvault"  # Path to the Key Vault module
  
  key_vault_name             = var.key_vault_name
  resource_group_name        = var.resource_group_name
  location                   = var.location
  tenant_id                  = var.tenant_id
  log_analytics_workspace_id = var.log_analytics_workspace_id
}

# Call the Disk Encryption Set module
module "disk_encryption_set" {
  source                   = "./modules/disk_encryption_set"
  disk_encryption_set_name = var.disk_encryption_set_name
  resource_group_name      = var.resource_group_name
  location                 = var.location
  key_vault_key_id         = module.nist_compliant_keyvault.key_vault_key_id
  key_vault_id             = module.nist_compliant_keyvault.key_vault_id
  tags                     = var.tags
}
