resource "tailscale_oauth_client" "k8s_operator" {
  description = "k8s-${var.cluster}"
  scopes      = ["devices:core", "auth_keys"]
  tags        = ["tag:k8s","tag:app","tag:cluster-${var.cluster}","tag:region-${var.region}"]
}
