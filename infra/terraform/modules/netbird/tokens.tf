resource "time_rotating" "k8s_operator_token" {
  rotation_days = 20
}

resource "netbird_token" "k8s_operator" {
  user_id         = netbird_user.k8s_operator.id
  name            = "Kubernetes Operator"
  expiration_days = 30

  lifecycle {
    replace_triggered_by = [time_rotating.k8s_operator_token]
  }
}
