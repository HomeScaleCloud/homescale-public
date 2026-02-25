resource "kubernetes_namespace" "onepassword" {
  depends_on = [digitalocean_kubernetes_cluster.mgmt]
  metadata {
    name = "onepassword"
  }
}

resource "kubernetes_namespace" "tailscale" {
  depends_on = [digitalocean_kubernetes_cluster.mgmt]
  metadata {
    name = "tailscale"
  }
}
