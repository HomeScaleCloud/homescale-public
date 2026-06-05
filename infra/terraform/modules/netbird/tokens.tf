resource "netbird_token" "k8s_operator" {
  user_id         = netbird_user.k8s_operator.id
  name            = "Kubernetes Operator"
  expiration_days = 30
}
