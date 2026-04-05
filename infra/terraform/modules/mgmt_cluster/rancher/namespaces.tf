resource "kubernetes_namespace_v1" "rancher" {
  metadata {
    name = "cattle-system"
  }
}

resource "kubernetes_namespace_v1" "prod" {
  metadata {
    name = "prod"
  }
}

resource "kubernetes_namespace_v1" "lab" {
  metadata {
    name = "lab"
  }
}
