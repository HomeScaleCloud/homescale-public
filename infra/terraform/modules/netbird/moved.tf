moved {
  from = netbird_dns_zone.metrics
  to   = netbird_dns_zone.app["metrics"]
}

moved {
  from = netbird_dns_record.grafana
  to   = netbird_dns_record.app_cname["REDACTED"]
}

moved {
  from = netbird_dns_record.alertmanager
  to   = netbird_dns_record.app_cname["REDACTED"]
}

moved {
  from = netbird_dns_record.prometheus
  to   = netbird_dns_record.app_cname["REDACTED"]
}

moved {
  from = netbird_dns_record.loki
  to   = netbird_dns_record.app_cname["REDACTED"]
}
