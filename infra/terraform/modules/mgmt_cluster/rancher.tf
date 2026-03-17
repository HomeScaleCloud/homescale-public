resource "helm_release" "rancher" {
  depends_on        = [digitalocean_kubernetes_cluster.mgmt, kubernetes_namespace_v1.rancher]
  name              = "rancher"
  namespace         = "cattle-system"
  chart             = "../../apps/rancher"
  dependency_update = true
}

resource "rancher2_bootstrap" "mgmt" {
  depends_on       = [data.kubernetes_secret_v1.rancher_bootstrap]
  count            = var.bootstrapped ? 1 : 0
  initial_password = data.kubernetes_secret_v1.rancher_bootstrap.data["bootstrapPassword"]
}

resource "rancher2_auth_config_azuread" "entraid" {
  depends_on         = [rancher2_bootstrap.mgmt]
  application_id     = data.onepassword_item.rancher_oidc.username
  application_secret = data.onepassword_item.rancher_oidc.password
  auth_endpoint      = "https://login.microsoftonline.com/${data.onepassword_item.entra_tenant.credential}/oauth2/v2.0/authorize"
  graph_endpoint     = "https://graph.microsoft.com"
  rancher_url        = "https://mgmt.tempel-carp.ts.net/verify-auth-azure"
  tenant_id          = data.onepassword_item.entra_tenant.credential
  token_endpoint     = "https://login.microsoftonline.com/${data.onepassword_item.entra_tenant.credential}/oauth2/v2.0/token"
}
