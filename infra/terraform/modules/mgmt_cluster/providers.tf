terraform {
  required_providers {
    digitalocean = {
      source = "digitalocean/digitalocean"
    }
    infisical = {
      source = "infisical/infisical"
    }
  }
}

provider "digitalocean" {
  token = var.digitalocean_token
}
