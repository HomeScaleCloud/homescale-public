resource "kubernetes_labels" "clusters_fleet_local" {
  api_version = "fleet.cattle.io/v1alpha1"
  kind        = "Cluster"
  metadata {
    name      = "local"
    namespace = "fleet-local"
  }
  labels = {
    "cluster.homescale.cloud/env" = "mgmt"
  }
}
