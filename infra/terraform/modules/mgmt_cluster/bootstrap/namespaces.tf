resource "kubernetes_namespace_v1" "onepassword" {
  metadata {
    name = "onepassword"
  }
}

resource "kubernetes_namespace_v1" "twingate" {
  metadata {
    name = "twingate"
  }
}
