# Scopes per Tailscale's own Kubernetes Operator Helm-install docs (General >
# Services RW, Devices > Core RW, Keys > Auth Keys RW). "Services" wasn't
# confirmed against the provider's scope table -- verify (and add if needed)
# once `terraform plan` runs against a real tailnet; see the plan's
# prerequisite section for the bootstrap credential this depends on.
resource "tailscale_oauth_client" "k8s_operator" {
  description = "Kubernetes Operator"
  scopes      = ["devices:core", "auth_keys"]
  tags        = ["tag:k8s-operator"]
}
