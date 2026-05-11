data "netbird_group" "all" {
  name = "All"
}

resource "netbird_group" "cluster_mgmt" {
  name = "cluster-mgmt"
}

resource "netbird_dns_zone" "mgmt" {
  name                 = "xxx"
  domain               = "xxx"
  enabled              = true
  enable_search_domain = false
  distribution_groups  = [data.netbird_group.all.id]
}

resource "netbird_dns_record" "rancher" {
  zone_id = netbird_dns_zone.mgmt.id
  name    = "xxx"
  type    = "CNAME"
  content = "xxx"
  ttl     = 300
}
