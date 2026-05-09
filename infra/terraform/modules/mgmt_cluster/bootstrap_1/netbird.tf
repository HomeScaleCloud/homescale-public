data "netbird_group" "all" {
  name = "All"
}

resource "netbird_dns_zone" "mgmt" {
  name                 = "xxx"
  domain               = "xxx"
  enabled              = true
  enable_search_domain = false
  distribution_groups  = [data.netbird_group.all.id]
}
