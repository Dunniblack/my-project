provider "kubernetes" {
  host                   = azurerm_kubernetes_cluster.default.kube_admin_config.0.host
  client_certificate     = base64decode(azurerm_kubernetes_cluster.default.kube_admin_config.0.client_certificate)
  client_key             = base64decode(azurerm_kubernetes_cluster.default.kube_admin_config.0.client_key)
  cluster_ca_certificate = base64decode(azurerm_kubernetes_cluster.default.kube_admin_config.0.cluster_ca_certificate)
}

resource "kubernetes_cluster_role_binding" "read-only" {
  count = (var.read_only_aad_group_id != null) ? 1 : 0

  metadata {
    name = "aks-view-binding-aad"
  }
  role_ref {
    api_group = "rbac.authorization.k8s.io"
    kind      = "ClusterRole"
    name      = "view"
  }
  subject {
    kind      = "Group"
    name      = var.read_only_aad_group_id
    api_group = "rbac.authorization.k8s.io"
  }
}
