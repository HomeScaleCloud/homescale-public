resource "digitalocean_kubernetes_cluster" "uk_lon_1_prod" {
  name    = "uk-lon-1-prod"
  region  = "lon1"
  version = "1.32.2-do.0"

  node_pool {
    name       = "uk-lon-1-prod-node"
    size       = "s-2vcpu-4gb"
    node_count = 2
  }
}
