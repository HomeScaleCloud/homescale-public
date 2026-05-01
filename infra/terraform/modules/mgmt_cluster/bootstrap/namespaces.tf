resource "kubernetes_namespace_v1" "onepassword" {
  metadata {
    name = "onepassword"
  }

  lifecycle {
    ignore_changes = [
      metadata[0].annotations["cattle.io/status"],
      metadata[0].annotations["lifecycle.cattle.io/create.namespace-auth"],
    ]
  }
}
