resource "twingate_remote_network" "mgmt" {
  name     = "${var.region}-mgmt"
  location = "ON_PREMISE"
}

resource "twingate_connector" "mgmt" {
  remote_network_id      = twingate_remote_network.mgmt.id
  status_updates_enabled = true
}

resource "twingate_connector_tokens" "mgmt" {
  connector_id = twingate_connector.mgmt.id
}
