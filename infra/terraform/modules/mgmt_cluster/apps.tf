resource "helm_release" "rancher" {
  name  = "rancher"
  chart = "../../../../apps/rancher"
}
