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

resource "kubernetes_namespace_v1" "prod" {
  depends_on = [digitalocean_kubernetes_cluster.mgmt]
  metadata {
    name = "prod"
  }
}

resource "kubernetes_namespace_v1" "test" {
  depends_on = [digitalocean_kubernetes_cluster.mgmt]
  metadata {
    name = "test"
  }
}

resource "kubernetes_namespace_v1" "lab" {
  depends_on = [digitalocean_kubernetes_cluster.mgmt]
  metadata {
    name = "lab"
  }
}
