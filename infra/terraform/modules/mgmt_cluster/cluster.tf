resource "digitalocean_kubernetes_cluster" "mgmt" {
  name    = "mgmt"
  region  = var.region
  version = var.k8s_version

  maintenance_policy {
    start_time = "04:00"
    day        = "sunday"
  }

  node_pool {
    name       = "node"
    size       = "s-2vcpu-4gb"
    node_count = 2
  }
}
