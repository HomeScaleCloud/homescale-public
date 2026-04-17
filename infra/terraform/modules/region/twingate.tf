resource "twingate_remote_network" "mgmt" {
  name     = "${var.region}-mgmt"
  location = "ON_PREMISE"
}

resource "twingate_connector" "mgmt" {
  remote_network_id      = twingate_remote_network.mgmt.id
  status_updates_enabled = true
  name                   = "${var.region}-mgmtr"
}

resource "twingate_connector_tokens" "mgmt" {
  connector_id = twingate_connector.mgmt.id
}

data "twingate_group" "team_infra_plat" {
  id = "R3JvdXA6ODEyMzI2"
}

data "twingate_security_policy" "high_risk" {
  name = "High Risk Policy"
}

resource "twingate_resource" "resource" {
  name              = "boa1-mgmt"
  address           = "10.1.245.0/24"
  remote_network_id = twingate_remote_network.mgmt.id

  security_policy_id = data.twingate_security_policy.high_risk.id
  protocols = {
    allow_icmp = true
    tcp = {
      policy = "RESTRICTED"
      ports  = ["80", "443", "10443", "22"]
    }
    udp = {
      policy = "RESTRICTED"
    }
  }

  access_policy {
    mode          = "AUTO_LOCK"
    approval_mode = "MANUAL"
    duration      = "8h"
  }

  access_group {
    group_id           = data.twingate_group.team_infra_plat.id
    security_policy_id = data.twingate_security_policy.high_risk.id
    access_policy {
      mode          = "AUTO_LOCK"
      approval_mode = "MANUAL"
      duration      = "8h"
    }
  }

  access_service {
    service_account_id = var.twingate_github_actions_service_account_id
  }
}
