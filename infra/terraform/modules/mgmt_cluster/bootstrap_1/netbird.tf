data "netbird_group" "all" {
  name = "All"
}

resource "netbird_group" "cluster_mgmt" {
  name = "REDACTED/name=mgmt"
}

resource "netbird_group" "app_rancher" {
  name = "app-rancher"
}

resource "netbird_dns_zone" "mgmt" {
  name                 = "REDACTED"
  domain               = "REDACTED"
  enabled              = true
  enable_search_domain = false
  distribution_groups  = [data.netbird_group.all.id]
}

resource "netbird_dns_record" "rancher" {
  zone_id = netbird_dns_zone.mgmt.id
  name    = "REDACTED"
  type    = "CNAME"
  content = "REDACTED"
  ttl     = 300
}
