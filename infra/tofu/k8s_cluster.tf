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
