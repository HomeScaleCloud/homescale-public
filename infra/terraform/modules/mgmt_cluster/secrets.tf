data "onepassword_vault" "k8s" {
  name = "k8s"
}

data "onepassword_item" "onepassword" {
  vault = "k8s"
  title = "onepassword"
}

data "onepassword_item" "entra_tenant" {
  vault = "k8s"
  title = "entra-tenant"
}

data "onepassword_item" "rancher_oidc" {
  vault = "k8s"
  title = "rancher-oidc"
}

resource "kubernetes_secret_v1" "onepassword" {
  depends_on = [kubernetes_namespace_v1.onepassword]
  count      = var.bootstrapped ? 1 : 0
  metadata {
    name      = "onepassword"
    namespace = "onepassword"
  }
  data = {
    credential = data.onepassword_item.onepassword.credential
    password   = data.onepassword_item.onepassword.password
  }
}

resource "kubernetes_secret_v1" "tailscale" {
  depends_on = [kubernetes_namespace_v1.tailscale]
  count      = var.bootstrapped ? 1 : 0
  metadata {
    name      = "operator-oauth"
    namespace = "tailscale"
  }
  data = {
    client_id     = tailscale_oauth_client.k8s_mgmt.id
    client_secret = tailscale_oauth_client.k8s_mgmt.key
  }
}

data "kubernetes_secret_v1" "rancher_bootstrap" {
  depends_on = [helm_release.rancher]
  metadata {
    name      = "bootstrap-secret"
    namespace = "cattle-system"
  }
}
