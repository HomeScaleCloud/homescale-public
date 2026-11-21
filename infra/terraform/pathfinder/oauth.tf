resource "tailscale_oauth_client" "k8s_operator" {
  description = "Kubernetes Operator"
  scopes      = ["devices:core", "auth_keys", "services"]
  tags        = ["tag:k8s"]

  # Avoids racing tag:k8s registration in tailscale_acl.this.
  depends_on = [tailscale_acl.this]
}
