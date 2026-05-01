resource "kubernetes_labels" "clusters_fleet_local" {
  api_version = "fleet.cattle.io/v1alpha1"
  kind        = "Cluster"
  metadata {
    name      = "local"
    namespace = "fleet-local"
  }
  labels = {
    "xxx/env"         = "mgmt"
    "xxx/rancher"         = "enabled"
    "xxx/ziti-controller" = "enabled"
    "xxx/external-dns"    = "enabled"
  }
}
