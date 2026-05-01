data "kubernetes_secret_v1" "rancher_bootstrap" {
  metadata {
    name      = "bootstrap-secret"
    namespace = "cattle-system"
  }
}
