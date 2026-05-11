resource "netbird_user" "k8s_operator" {
  is_service_user = true
  name            = "Kubernetes Operator"
  is_blocked      = false
  role            = "admin"
}
