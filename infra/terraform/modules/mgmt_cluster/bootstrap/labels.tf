resource "kubernetes_labels" "clusters_fleet_local" {
  api_version = "fleet.cattle.io/v1alpha1"
  kind        = "Cluster"
  metadata {
    name      = "local"
    namespace = "fleet-local"
  }
  labels = {
    "REDACTED/env"         = "mgmt"
    "REDACTED/rancher"         = "enabled"
    "REDACTED/ziti-controller" = "enabled"
    "REDACTED/external-dns"    = "enabled"
  }
}
