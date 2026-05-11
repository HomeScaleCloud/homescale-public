data "netbird_group" "env_mgmt" {
  name = "env-mgmt"
}

data "netbird_group" "net_region_mgmt" {
  name = "net-region-mgmt"
}

resource "netbird_network" "mgmt" {
  name = "${var.region}-mgmt"
}

resource "netbird_group" "region_mgmt" {
  name = "${var.region}-mgmt"
}

resource "netbird_network_router" "mgmt" {
  network_id  = netbird_network.mgmt.id
  peer_groups = [netbird_group.region_mgmt.id]
}

resource "netbird_network_resource" "mgmt" {
  network_id = netbird_network.mgmt.id
  name       = "${var.region}-mgmt"
  address    = var.mgmt_cidr
  groups     = [netbird_group.region_mgmt.id, data.netbird_group.env_mgmt.id, data.netbird_group.net_region_mgmt.id]
  enabled    = true
}

data "netbird_group" "net_region_bmc" {
  name = "net-region-bmc"
}

resource "netbird_network" "bmc" {
  name = "${var.region}-bmc"
}

resource "netbird_group" "region_bmc" {
  name = "${var.region}-bmc"
}

resource "netbird_network_router" "bmc" {
  network_id  = netbird_network.bmc.id
  peer_groups = [netbird_group.region_bmc.id]
}

resource "netbird_network_resource" "bmc" {
  network_id = netbird_network.bmc.id
  name       = "${var.region}-bmc"
  address    = var.bmc_cidr
  groups     = [netbird_group.region_bmc.id, data.netbird_group.env_mgmt.id, data.netbird_group.net_region_bmc.id]
  enabled    = true
}

resource "netbird_setup_key" "region_router" {
  name                   = "${var.region}-router"
  expiry_seconds         = 86400
  type                   = "reusable"
  allow_extra_dns_labels = true
  auto_groups            = [netbird_group.region_mgmt.id, netbird_group.region_bmc.id, data.netbird_group.env_mgmt.id, data.netbird_group.net_region_mgmt.id, data.netbird_group.net_region_bmc.id]
  ephemeral              = false
  usage_limit            = 3
}
