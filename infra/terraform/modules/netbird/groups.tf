data "netbird_group" "all" {
  name = "All"
}

data "netbird_group" "team_infra_plat" {
  name = "team-infra-plat"
}

data "netbird_group" "team_sec_plat" {
  name = "team-sec-plat"
}

data "netbird_group" "sg_k8s_admin" {
  name = "sg-k8s-admin"
}

data "netbird_group" "sg_ssh_admin" {
  name = "sg-ssh-admin"
}

data "netbird_group" "net_region_mgmt" {
  name = "net-region-mgmt"
}

data "netbird_group" "net_region_bmc" {
  name = "net-region-bmc"
}

resource "netbird_group" "region_routers" {
  name = "region-routers"
}

resource "netbird_group" "k8s" {
  name = "k8s"
}

resource "netbird_group" "github_actions" {
  name = "GitHub Actions"
}

resource "netbird_group" "net_region_mgmt" {
  name = "net-region-mgmt"
}

resource "netbird_group" "net_region_bmc" {
  name = "net-region-bmc"
}

resource "netbird_group" "node_metal" {
  name = "node-metal"
}

locals {
  app_names = sort(distinct([
    for app_file in fileset("${path.module}/../../../../apps", "*/**") : split("/", app_file)[0]
  ]))

  cluster_names = sort(distinct([
    for cluster_file in fileset("${path.module}/../../../../clusters", "*/**") : split("/", cluster_file)[0]
  ]))
}

resource "netbird_group" "app" {
  for_each = toset(local.app_names)

  name = "app-${each.key}"
}

resource "netbird_group" "cluster" {
  for_each = toset(local.cluster_names)

  name = "cluster-${each.key}"
}
