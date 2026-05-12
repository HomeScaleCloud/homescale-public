resource "rancher2_cluster_v2" "harvester" {
  name               = "metal-${var.region}"
  fleet_namespace    = "metal"
  kubernetes_version = "v1.34.2+rke2r1"
}
