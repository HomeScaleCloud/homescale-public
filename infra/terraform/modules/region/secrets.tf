data "onepassword_vault" "k8s" {
  name = "k8s"
}

resource "onepassword_item" "twingate_mgmt_access" {
  vault    = data.onepassword_vault.k8s.uuid
  title    = "tg-connector-${var.region}-mgmt-access"
  password = twingate_connector_tokens.mgmt.access_token
}

resource "onepassword_item" "twingate_mgmt_refresh" {
  vault    = data.onepassword_vault.k8s.uuid
  title    = "tg-connector-${var.region}-mgmt-refresh"
  password = twingate_connector_tokens.mgmt.refresh_token
}
