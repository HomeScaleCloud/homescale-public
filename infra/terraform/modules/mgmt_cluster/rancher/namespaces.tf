resource "kubernetes_namespace_v1" "prod" {
  metadata {
    name = "prod"
  }

  lifecycle {
    ignore_changes = [
      metadata[0].annotations["cattle.io/status"],
      metadata[0].annotations["lifecycle.cattle.io/create.namespace-auth"],
    ]
  }
}

resource "kubernetes_namespace_v1" "lab" {
  metadata {
    name = "lab"
  }

  lifecycle {
    ignore_changes = [
      metadata[0].annotations["cattle.io/status"],
      metadata[0].annotations["lifecycle.cattle.io/create.namespace-auth"],
    ]
  }
}
