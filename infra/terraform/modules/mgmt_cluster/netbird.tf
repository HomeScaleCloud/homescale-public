data "netbird_group" "all" {
  name = "All"
}

resource "netbird_group" "cluster_mgmt" {
  name = "cluster-mgmt"
}

resource "netbird_dns_zone" "mgmt" {
  name                 = "REDACTED"
  domain               = "REDACTED"
  enabled              = true
  enable_search_domain = false
  distribution_groups  = [data.netbird_group.all.id]
}
