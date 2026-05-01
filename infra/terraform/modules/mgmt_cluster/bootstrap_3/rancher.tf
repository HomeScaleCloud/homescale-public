resource "rancher2_bootstrap" "mgmt" {
  depends_on       = [data.kubernetes_secret_v1.rancher_bootstrap]
  initial_password = data.kubernetes_secret_v1.rancher_bootstrap.data["bootstrapPassword"]
}
