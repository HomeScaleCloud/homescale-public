resource "helm_release" "rancher" {
  name              = "rancher"
  namespace         = "cattle-system"
  chart             = "../../apps/rancher"
  dependency_update = true
}

resource "helm_release" "onepassword" {
  name              = "onepassword"
  namespace         = "onepassword"
  chart             = "../../apps/onepassword"
  dependency_update = true
}
