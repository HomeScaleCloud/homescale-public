resource "netbird_dns_zone" "cluster" {
  for_each = toset(local.cluster_names)

  name                 = "${each.key}xxx"
  domain               = "${each.key}xxx"
  enabled              = true
  enable_search_domain = false
  distribution_groups  = [data.netbird_group.all.id]
}
