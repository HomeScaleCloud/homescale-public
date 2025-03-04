resource "vultr_kubernetes" "uk_lon_1_mgmt" {
  region          = "lhr"
  label           = "uk-lon-1-mgmt"
  version         = "v1.31.5+1"
  enable_firewall = true


  node_pools {
    node_quantity = 2
    plan          = "vc2-2c-4gb"
    label         = "uk-lon-1-mgmt-node"
  }
}

resource "digitalocean_kubernetes_cluster" "uk_lon_1_mgmt" {
  name    = "uk-lon-1-mgmt"
  region  = "lon1"
  version = "1.32.1-do.0"

  node_pool {
    name       = "uk-lon-1-mgmt-node"
    size       = "s-2vcpu-4gb"
    node_count = 2
  }
}
