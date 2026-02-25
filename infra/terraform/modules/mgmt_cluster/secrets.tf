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

resource "kubernetes_secret" "onepassword" {
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