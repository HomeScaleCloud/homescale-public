resource "netbird_dns_record" "omni" {
  zone_id = netbird_dns_zone.cluster["mgmt"].id
  name    = "xxx"
  type    = "CNAME"
  content = "xxx"
  ttl     = 300
}

resource "netbird_dns_zone" "metrics" {
  name                 = "xxx"
  domain               = "xxx"
  enabled              = true
  enable_search_domain = false
  distribution_groups  = [data.netbird_group.all.id]
}

resource "netbird_dns_record" "grafana" {
  zone_id = netbird_dns_zone.metrics.id
  name    = "xxx"
  type    = "CNAME"
  content = "xxx"
  ttl     = 300
}
