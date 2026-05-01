data "digitalocean_kubernetes_versions" "version" {
  version_prefix = var.k8s_version
}

resource "digitalocean_kubernetes_cluster" "mgmt" {
  name         = "mgmt"
  region       = var.region
  auto_upgrade = true
  version      = data.digitalocean_kubernetes_versions.version.latest_version

  maintenance_policy {
    start_time = "04:00"
    day        = "sunday"
  }

  node_pool {
    name       = "mgmt-node"
    size       = "s-2vcpu-4gb"
    node_count = 2
  }
}
