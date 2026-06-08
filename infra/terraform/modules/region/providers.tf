terraform {
  required_providers {
    infisical = {
      source = "infisical/infisical"
    }
    netbird = {
      source = "netbirdio/netbird"
    }
  }
}

provider "netbird" {
  token = var.netbird_token
}
