resource "netbird_reverse_proxy_service" "app" {
  name   = var.name
  domain = var.domain

  targets = [for id in data.netbird_peers.peers.ids : {
    target_id   = id
    target_type = "peer"
    port        = tonumber(var.port)
    protocol    = var.protocol
  }]

  auth = {}
}
