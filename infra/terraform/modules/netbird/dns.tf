resource "netbird_dns_record" "omni" {
  zone_id = netbird_dns_zone.cluster["mgmt"].id
  name    = "REDACTED"
  type    = "CNAME"
  content = "REDACTED"
  ttl     = 300
}

resource "netbird_dns_zone" "metrics" {
  name                 = "REDACTED"
  domain               = "REDACTED"
  enabled              = true
  enable_search_domain = false
  distribution_groups  = [data.netbird_group.all.id]
}

resource "netbird_dns_record" "grafana" {
  zone_id = netbird_dns_zone.metrics.id
  name    = "REDACTED"
  type    = "CNAME"
  content = "REDACTED"
  ttl     = 300
}

resource "netbird_dns_record" "prometheus" {
  zone_id = netbird_dns_zone.metrics.id
  name    = "REDACTED"
  type    = "CNAME"
  content = "REDACTED"
  ttl     = 300
}
