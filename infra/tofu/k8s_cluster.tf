resource "digitalocean_kubernetes_cluster" "core" {
  name    = "core"
  region  = "lon1"
  version = "1.31.1-do.5"

  node_pool {
    name       = "core-node"
    size       = "s-2vcpu-4gb"
    node_count = 2
  }
}

resource "vultr_kubernetes" "uk_lon_1_cp" {
  region          = "lhr"
  label           = "uk-lon-1"
  version         = "v1.32.1+1"
  enable_firewall = true


  node_pools {
    node_quantity = 2
    plan          = "vc2-2c-4gb"
    label         = "uk-lon-1-cp-node"
  }
}
