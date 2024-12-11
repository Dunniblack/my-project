resource "azurerm_user_assigned_identity" "acr" {
  count               = 1
  location            = var.location
  name                = "${module.name-map.container_registry_name}-identity" 
  resource_group_name = azurerm_resource_group.global.name
}

resource "azurerm_key_vault_access_policy" "acr" {
  count        = 1
  key_vault_id = module.resources.c1_key_vault.id
  tenant_id    = module.resources.azure_config.tenant_id
  object_id    = azurerm_user_assigned_identity.acr.0.principal_id

  key_permissions = [
    "Get",
    "UnwrapKey",
    "WrapKey"
  ]
}

resource "azurerm_key_vault_key" "acr" {
  count        = 1
  name         = "${module.name-map.container_registry_name}-encryption-key"
  key_vault_id = module.resources.c1_key_vault.id
  key_type     = "RSA"
  key_size     = 2048

  key_opts = [
    "decrypt",
    "encrypt",
    "sign",
    "unwrapKey",
    "verify",
    "wrapKey",
  ]

  rotation_policy {
    automatic {
      time_before_expiry = "P30D"
    }

    expire_after         = "P90D"
    notify_before_expiry = "P29D"
  }

  depends_on = [
    azurerm_key_vault_access_policy.service_principal
  ]
}

resource "azurerm_container_registry" "acr" {
  count                         = 1
  name                          = module.name-map.container_registry_name
  resource_group_name           = azurerm_resource_group.global.name
  location                      = var.location
  sku                           = "Premium"
  admin_enabled                 = true
  public_network_access_enabled = local.acr_public
  anonymous_pull_enabled        = false
  export_policy_enabled         = local.acr_public
  quarantine_policy_enabled     = false
  #Content trust is currently not supported for encryption enabled registries.
  trust_policy_enabled          = false
  zone_redundancy_enabled       = true
  retention_policy_in_days      = 30

  identity {
    type = "UserAssigned"
    identity_ids = [
      azurerm_user_assigned_identity.acr.0.id
    ]
  }

  # 400 Bad Request - IP Range cannot overlap with private or reserved IPs 10.0.0.0/8
  #network_rule_set {
  #  default_action = "Deny"
  #  ip_rule {
  #    action  = "Allow"
  #    ip_range = module.resources.vnet.address_space.0
  #  }
  #}

  encryption {
    key_vault_key_id   = azurerm_key_vault_key.acr.0.id
    identity_client_id = azurerm_user_assigned_identity.acr.0.client_id
  }
}

resource "azurerm_monitor_diagnostic_setting" "acr" {
  count                      = 1
  name                       = "acr-diagnostics"
  target_resource_id         = azurerm_container_registry.acr.0.id
  log_analytics_workspace_id = module.resources.c1_log_analytics_workspace.id

  enabled_log {
    category_group = "allLogs"
  }

  metric {
    category = "AllMetrics"
  }
}

resource "azurerm_private_dns_zone" "acr" {
  count               = 1
  name                = "privatelink.azurecr.us"
  resource_group_name = azurerm_resource_group.global.name
}

resource "azurerm_private_dns_zone_virtual_network_link" "acr_link_default" {
  count                 = 1
  name                  = "acr-link-default"
  resource_group_name   = azurerm_resource_group.global.name
  private_dns_zone_name = azurerm_private_dns_zone.acr.0.name
  virtual_network_id    = module.resources.vnet.id
  registration_enabled  = false
}

resource "azurerm_key_vault_secret" "acr-user-1" {
  count        = 1
  name         = "acr-user-1"
  value        = azurerm_container_registry.acr.0.admin_username
  key_vault_id = module.resources.c1_key_vault.id

  depends_on = [
    azurerm_key_vault_access_policy.service_principal
  ]
}

resource "azurerm_key_vault_secret" "acr-password-1" {
  count        = 1
  name         = "acr-password-1"
  value        = azurerm_container_registry.acr.0.admin_password
  key_vault_id = module.resources.c1_key_vault.id

  depends_on = [
    azurerm_key_vault_access_policy.service_principal
  ]
}
