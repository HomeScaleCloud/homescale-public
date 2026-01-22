data "onepassword_vault" "cluster" {
  name = var.cluster
}

data "onepassword_item" "onepassword" {
  vault = var.cluster
  title = "onepassword"
}

data "onepassword_item" "argocd_oidc" {
  vault = "common"
  title = "argocd-oidc"
}

data "onepassword_item" "entra_tenant" {
  vault = "common"
  title = "entra-tenant"
}

resource "kubernetes_secret" "onepassword" {
  count      = (var.init_stage_1 || var.init_stage_2) ? 0 : 1
  depends_on = [kubernetes_namespace.onepassword]
  metadata {
    name      = "onepassword"
    namespace = "onepassword"
  }
  data = {
    credential = data.onepassword_item.onepassword.credential
    password   = data.onepassword_item.onepassword.password
  }
}

resource "kubernetes_secret" "tailscale" {
  count      = (var.init_stage_1 || var.init_stage_2) ? 0 : 1
  depends_on = [kubernetes_namespace.tailscale]
  metadata {
    name      = "operator-oauth"
    namespace = "tailscale"
  }
  data = {
    client_id     = tailscale_oauth_client.k8s_operator.id
    client_secret = tailscale_oauth_client.k8s_operator.key
  }
}
