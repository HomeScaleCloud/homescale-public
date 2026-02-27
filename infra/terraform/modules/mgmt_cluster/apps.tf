resource "helm_release" "rancher" {
  depends_on        = [digitalocean_kubernetes_cluster.mgmt, kubernetes_namespace_v1.rancher]
  name              = "rancher"
  namespace         = "cattle-system"
  chart             = "../../apps/rancher"
  dependency_update = true
}

resource "helm_release" "onepassword" {
  depends_on        = [digitalocean_kubernetes_cluster.mgmt, kubernetes_secret_v1.onepassword]
  name              = "onepassword"
  namespace         = "onepassword"
  chart             = "../../apps/onepassword"
  dependency_update = true
}
