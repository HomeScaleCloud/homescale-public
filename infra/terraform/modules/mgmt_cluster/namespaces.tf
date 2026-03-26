resource "kubernetes_namespace_v1" "onepassword" {
  depends_on = [digitalocean_kubernetes_cluster.mgmt]
  count      = var.bootstrapped ? 1 : 0
  metadata {
    name = "onepassword"
  }
}

resource "kubernetes_namespace_v1" "rancher" {
  depends_on = [digitalocean_kubernetes_cluster.mgmt]
  metadata {
    name = "cattle-system"
  }
}

resource "kubernetes_namespace_v1" "twingate" {
  depends_on = [digitalocean_kubernetes_cluster.mgmt]
  metadata {
    name = "twingate"
  }
}

resource "kubernetes_namespace_v1" "prod" {
  depends_on = [digitalocean_kubernetes_cluster.mgmt]
  count      = var.bootstrapped ? 1 : 0
  metadata {
    name = "prod"
  }
}

resource "kubernetes_namespace_v1" "lab" {
  depends_on = [digitalocean_kubernetes_cluster.mgmt]
  count      = var.bootstrapped ? 1 : 0
  metadata {
    name = "lab"
  }
}
