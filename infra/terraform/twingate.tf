resource "time_rotating" "twingate_service_key_rotation" {
  rotation_days = 30
}

resource "time_static" "twingate_service_key_rotation" {
  rfc3339 = time_rotating.twingate_service_key_rotation.rfc3339
}

resource "twingate_service_account" "github_actions" {
  name = "GitHub Actions"
}

resource "twingate_service_account_key" "github_actions" {
  name               = "GitHub Actions"
  service_account_id = twingate_service_account.github_actions.id
  lifecycle {
    replace_triggered_by = [time_static.twingate_service_key_rotation]
  }
}
