

# resource "kubernetes_namespace" "onepassword" {
#   metadata { name = "onepassword" }
# }

resource "tailscale_oauth_client" "k8s_operator" {
  description = "k8s-${var.cluster}"
  scopes      = ["devices:core", "auth_keys"]
  tags        = ["tag:k8s-operator", "tag:app", "tag:k8s-api"]
}
