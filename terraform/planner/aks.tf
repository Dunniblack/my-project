data "azurerm_key_vault_secret" "sp_app_id" {
  name         = "spAppId"
  key_vault_id = module.resources.c1_key_vault.id
}

data "azurerm_key_vault_secret" "sp_app_key" {
  name         = "spAppKey"
  key_vault_id = module.resources.c1_key_vault.id
}

resource "azurerm_kubernetes_cluster" "default" {
  name                                = module.name-map.aks_name
  location                            = var.location
  resource_group_name                 = azurerm_resource_group.default.name
  node_resource_group                 = "${azurerm_resource_group.default.name}-${var.environment_name}-node-01"
  #'none' not allowed for automatic_upgrade_channel
  #automatic_upgrade_channel           = "stable"
  #Cost analysis can only be enabled on a cluster with a system assigned or user assigned managed identity.
  cost_analysis_enabled               = false
  disk_encryption_set_id              = azurerm_disk_encryption_set.default.id
  dns_prefix                          = lower(module.name-map.aks_name)
  image_cleaner_enabled               = true
  image_cleaner_interval_hours        = 24
  kubernetes_version                  = local.kubernetes_version
  #TODO:FIXME - disable K8s local accts if possible
  local_account_disabled              = false
  node_os_upgrade_channel             = "NodeImage"
  oidc_issuer_enabled                 = false
  open_service_mesh_enabled           = false
  private_cluster_enabled             = true 
  private_dns_zone_id                 = "System"
  private_cluster_public_fqdn_enabled = false
  workload_identity_enabled           = false
  role_based_access_control_enabled   = true
  run_command_enabled                 = true
  sku_tier                            = "Premium"
  support_plan                        = "KubernetesOfficial"

  default_node_pool {
    name                          = "default"
    node_count                    = 4
    vm_size                       = "Standard_DS2_v2"
    host_encryption_enabled       = true
    auto_scaling_enabled          = false
    node_public_ip_enabled        = true
    #TODO:FIXME - Add this property when ready
    #host_group_id                 =
    fips_enabled                  = true
    kubelet_disk_type             = "OS"
    max_pods                      = 125
    node_labels                   = {
      "node" = "default"
    }
    only_critical_addons_enabled  = true
    os_disk_size_gb               = 200
    os_sku                        = "AzureLinux"
    #NetworkPluginMode overlay cannot be used with PodSubnetID
    #pod_subnet_id                 = module.resources.subnet.id
    temporary_name_for_rotation   = "tempname"
    type                          = "VirtualMachineScaleSets"
    #Availability zone is required for UltraSSD setting.
    ultra_ssd_enabled             = false
    vnet_subnet_id                = module.resources.subnet.id
    workload_runtime              = "OCIContainer"
  
    node_network_profile {
      allowed_host_ports {
        port_start = 53
        port_end   = 53
        protocol   = "UDP"
      }
    }

    upgrade_settings {
      drain_timeout_in_minutes      = 0
      max_surge                     = "10%"
      node_soak_duration_in_minutes = 0
    }

    #TODO:FIXME add this if applicable 
    #kubelet_config {}
    #linux_os_config {}
  }

  service_principal {
    client_id     = data.azurerm_key_vault_secret.sp_app_id.value
    client_secret = data.azurerm_key_vault_secret.sp_app_key.value
  }    

  azure_active_directory_role_based_access_control {
    azure_rbac_enabled     = true
    tenant_id              = module.resources.azure_config.tenant_id
    admin_group_object_ids = [
      var.admin_aad_group_id
    ]
  }

  storage_profile  {
    blob_driver_enabled         = true
    disk_driver_enabled         = true
    file_driver_enabled         = true
    snapshot_controller_enabled = true
  }

  # Vnet integration should be enabled when KeyVault network access is Private.
  #key_management_service {
  #  key_vault_key_id         = azurerm_key_vault_key.disk_encryption_set.id
  #  key_vault_network_access = "Private"
  #}

  key_vault_secrets_provider {
    secret_rotation_enabled  = true
    secret_rotation_interval = "1h"
  }

  network_profile {
    network_mode        = "transparent"
    network_plugin      = "azure"
    network_policy      = "cilium"
    network_data_plane  = "cilium"
    network_plugin_mode = "overlay"
  
    outbound_type       = "loadBalancer"
    load_balancer_sku   = "standard"
    load_balancer_profile {
      #An argument named "backend_pool_type" is not expected here.
      #backend_pool_type         = "NodeIPConfiguration"
      idle_timeout_in_minutes   = 30
      managed_outbound_ip_count = 3
      outbound_ports_allocated  = 0
    }
  }

  linux_profile {
    admin_username = "sysadmin"
    ssh_key {
      # TODO:FIXME - make this dynamic
      key_data = "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABgQC4AyMjGu88FL794nklFbMhr5Gc7aT9C2G0elfF9vR0mFJ+Dgs1zZwwuavIUpXJQqqjhQd7ka1Z9olENbaHlIXMTl7t/jGLzh9oUbkk/sboOvKJtXKVVAtucuVVVNl29Yu2s6kHlpSYUt8hF/h2dOH4Le2sLQiyCEpLOosKSzpzdW+o/5JtllN1wCTaCW3XWJXffHjhCeHQ62muwx9CF0AYJL3AK5JMDwby9u1/DDNWVTGAaaF+LSqqL+xG8rWq5Sw4Y3SCJgojDac2eeCPmnhhxSV6S8IiqiJ9AklsRwYTrWHGCiODjLohK4WPu0m0fQ7RZ578hgL/lFv+CL5d4jcgzx+I+HPTsAS5mxWWoVdIfWLU22CZwWBPe+2xtpy9RPG5mxuAoIL1pIyvdsCB9OviEmYvH4HADNoECx5MtSU2fg8xTMU/yWMWkrEuw1kbE35IIj5gnDc5plG5Jx6w6FBI6kYk8qHNRnTuRN8EQyPya2fcACHZyR/4QHzOk1ykpSk="
    }
  }

  microsoft_defender {
    log_analytics_workspace_id = module.resources.c1_log_analytics_workspace.id
  }

  #TODO:FIXME add this if applicable 
  #maintenance_window {}
  #maintenance_window_auto_upgrade {}
  #maintenance_window_node_os {}

  #Private cluster cannot be enabled with AuthorizedIPRanges.
  #api_server_access_profile {
  #    authorized_ip_ranges = module.resources.vnet.address_space
  #}

  #OpenServiceMesh addon is incompatible with feature Azure Service Mesh.
  #service_mesh_profile {
  #  mode      = "Istio"
  #  revisions = ["asm-1-20"]
  #}

  #Application Gateway Ingress Controller addon is not supported with Azure CNI Overlay.
  #ingress_application_gateway {}

  depends_on = [
    azurerm_key_vault_access_policy.service_principal
  ]

  lifecycle {
    ignore_changes = [
      default_node_pool.0.node_count
    ]
  }
}

resource "azurerm_monitor_diagnostic_setting" "aks" {
  name                       = "aks-diagnostics"
  target_resource_id         = azurerm_kubernetes_cluster.default.id
  log_analytics_workspace_id = module.resources.c1_log_analytics_workspace.id

  # Enable logging for all categories
  enabled_log {
    category = "kube-audit"
  }
  enabled_log {
    category = "kube-apiserver"
  }
  enabled_log {
    category = "kube-audit-admin"
  }
  enabled_log {
    category = "kube-controller-manager"
  }
  enabled_log {
    category = "kube-scheduler"
  }
  enabled_log {
    category = "cloud-controller-manager"
  }
  enabled_log {
    category = "guard"
  }
  enabled_log {
    category = "cluster-autoscaler"
  }
  enabled_log {
    category = "csi-azuredisk-controller"
  }
  enabled_log {
    category = "csi-azurefile-controller"
  }
  enabled_log {
    category = "csi-snapshot-controller"
  }

  # Enable metrics for AllMetrics category
  metric {
    category = "AllMetrics"
  }
}
