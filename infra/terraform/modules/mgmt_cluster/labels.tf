resource "kubernetes_labels" "clusters_fleet_local" {
  depends_on  = [helm_release.rancher]
  count       = var.bootstrapped ? 1 : 0
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
