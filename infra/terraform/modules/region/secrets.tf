data "onepassword_item" "twingate" {
  vault = "github-actions"
  title = "twingate"
}

data "onepassword_vault" "k8s" {
  name = "k8s"
}

resource "onepassword_item" "twingate_mgmt" {
  vault    = data.onepassword_vault.k8s.id
  title    = "twingate-connector-${var.region}-mgmt"
  password = twingate_connector_tokens.mgmt.access_token
}
