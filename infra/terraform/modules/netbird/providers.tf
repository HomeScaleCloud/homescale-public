terraform {
  required_providers {
    netbird = {
      source = "netbirdio/netbird"
    }
    infisical = {
      source = "infisical/infisical"
    }
  }
}

provider "netbird" {
  token = var.netbird_token
}
