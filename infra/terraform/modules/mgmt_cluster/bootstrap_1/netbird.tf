data "netbird_group" "all" {
  name = "All"
}

resource "netbird_dns_zone" "mgmt" {
  name                 = "mgmt"
  domain               = "xxx"
  enabled              = true
  enable_search_domain = true
  distribution_groups  = [data.netbird_group.all.id]
}
