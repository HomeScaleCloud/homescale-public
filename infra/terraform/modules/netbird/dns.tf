resource "netbird_dns_record" "omni" {
  zone_id = netbird_dns_zone.cluster["mgmt"].id
  name    = "REDACTED"
  type    = "CNAME"
  content = "REDACTED"
  ttl     = 300
}

resource "netbird_dns_record" "kubeapi" {
  for_each = netbird_dns_zone.cluster

  zone_id = each.value.id
  name    = "k8s.${each.key}REDACTED"
  type    = "CNAME"
  content = "${each.key}REDACTED"
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

resource "netbird_dns_record" "alertmanager" {
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

resource "netbird_dns_record" "loki" {
  zone_id = netbird_dns_zone.metrics.id
  name    = "REDACTED"
  type    = "CNAME"
  content = "REDACTED"
  ttl     = 300
}
