resource "kubernetes_namespace_v1" "onepassword" {
  depends_on = [digitalocean_kubernetes_cluster.mgmt]
  metadata {
    name = "onepassword"
  }
}

resource "kubernetes_namespace_v1" "tailscale" {
  depends_on = [digitalocean_kubernetes_cluster.mgmt]
  metadata {
    name = "tailscale"
  }
}

resource "kubernetes_namespace_v1" "rancher" {
  depends_on = [digitalocean_kubernetes_cluster.mgmt]
  metadata {
    name = "cattle-system"
  }
}
