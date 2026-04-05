resource "rancher2_auth_config_azuread" "entraid" {
  application_id     = data.onepassword_item.rancher_oidc.username
  application_secret = data.onepassword_item.rancher_oidc.password
  auth_endpoint      = "https://login.microsoftonline.com/${data.onepassword_item.entra_tenant.credential}/oauth2/v2.0/authorize"
  graph_endpoint     = "https://graph.microsoft.com"
  rancher_url        = "https://mgmt.homescale.cloud/verify-auth-azure"
  tenant_id          = data.onepassword_item.entra_tenant.credential
  token_endpoint     = "https://login.microsoftonline.com/${data.onepassword_item.entra_tenant.credential}/oauth2/v2.0/token"
}
