resource "tailscale_oauth_client" "k8s_operator" {
  description = "Kubernetes Operator"
  scopes      = ["devices:core", "auth_keys", "services:read", "services:write"]
  tags        = ["tag:k8s"]

  # Without this, Terraform may create this in parallel with tailscale_acl.this
  # and race the tag:k8s registration, failing with "requested tags ... invalid
  # or not permitted".
  depends_on = [tailscale_acl.this]
}
