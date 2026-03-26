resource "helm_release" "rancher" {
  depends_on        = [digitalocean_kubernetes_cluster.mgmt, kubernetes_namespace_v1.rancher]
  name              = "rancher"
  namespace         = "cattle-system"
  chart             = "../../apps/rancher"
  dependency_update = true
}

resource "rancher2_bootstrap" "mgmt" {
  depends_on       = [data.kubernetes_secret_v1.rancher_bootstrap]
  provider         = rancher2.bootstrap
  count            = var.bootstrapped ? 1 : 0
  initial_password = data.kubernetes_secret_v1.rancher_bootstrap.data["bootstrapPassword"]
}

resource "rancher2_auth_config_azuread" "entraid" {
  depends_on         = [rancher2_bootstrap.mgmt]
  application_id     = data.onepassword_item.rancher_oidc.username
  application_secret = data.onepassword_item.rancher_oidc.password
  auth_endpoint      = "https://login.microsoftonline.com/${data.onepassword_item.entra_tenant.credential}/oauth2/v2.0/authorize"
  graph_endpoint     = "https://graph.microsoft.com"
  rancher_url        = "https://mgmt.homescale.cloud/verify-auth-azure"
  tenant_id          = data.onepassword_item.entra_tenant.credential
  token_endpoint     = "https://login.microsoftonline.com/${data.onepassword_item.entra_tenant.credential}/oauth2/v2.0/token"
}

resource "rancher2_global_role_binding" "sg_k8s_admin" {
  depends_on         = [rancher2_auth_config_azuread.entraid]
  name               = "sg-k8s-admin"
  global_role_id     = "admin"
  group_principal_id = "azuread_group://4d4167e8-204c-4328-b5f4-4dae634d46a8"
}
