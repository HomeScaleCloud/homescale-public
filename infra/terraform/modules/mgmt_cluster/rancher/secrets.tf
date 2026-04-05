data "onepassword_item" "entra_tenant" {
  vault = "k8s"
  title = "entra-tenant"
}

data "onepassword_item" "rancher_oidc" {
  vault = "k8s"
  title = "rancher-oidc"
}
