resource "harvester_clusternetwork" "mgmt" {
  name = "${var.region}-mgmt"
}

resource "harvester_network" "mgmt" {
  name                 = "${var.region}-mgmt"
  namespace            = "harvester-public"
  vlan_id              = 1
  route_mode           = "auto"
  route_dhcp_server_ip = ""
  cluster_network_name = harvester_clusternetwork.mgmt.name
}

resource "harvester_vlanconfig" "mgmt" {
  name                 = "${var.region}-mgmt"
  cluster_network_name = harvester_clusternetwork.mgmt.name

  lifecycle {
    ignore_changes = [
      uplink[0].bond_miimon,
    ]
  }

  uplink {
    nics = [
      "eno2"
    ]
    bond_mode = "active-backup"
    mtu       = 1500
  }
}
