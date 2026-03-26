data "onepassword_item" "twingate" {
  vault = "github-actions"
  title = "twingate"
}

resource "onepassword_item" "twingate_mgmt" {
  vault    = "k8s"
  title    = "twingate-connector-mgmt"
  password = twingate_connector_tokens.mgmt.access_token
}
