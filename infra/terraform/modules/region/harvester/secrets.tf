data "onepassword_item" "harvester_kubeconfig" {
  vault = "k8s"
  title = "metal-${var.region}-kubeconfig"
}