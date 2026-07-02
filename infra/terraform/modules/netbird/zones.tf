resource "netbird_dns_zone" "cluster" {
  for_each = toset(local.cluster_names)

  name                 = "${each.key}REDACTED"
  domain               = "${each.key}REDACTED"
  enabled              = true
  enable_search_domain = false
  distribution_groups  = [data.netbird_group.all.id]
}

resource "netbird_dns_zone" "app" {
  for_each = local.netbird_cname_apps

  name                 = "${each.key}REDACTED"
  domain               = "${each.key}REDACTED"
  enabled              = true
  enable_search_domain = false
  distribution_groups  = [data.netbird_group.all.id]
}
