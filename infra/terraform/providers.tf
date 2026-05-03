terraform {
  required_providers {
    onepassword = {
      source  = "1Password/onepassword"
      version = "2.2.1"
    }
    cloudflare = {
      source  = "cloudflare/cloudflare"
      version = "5.19.1"
    }
    digitalocean = {
      source  = "digitalocean/digitalocean"
      version = "2.85.0"
    }
    rancher2 = {
      source  = "rancher/rancher2"
      version = "14.1.0"
    }
    helm = {
      source  = "hashicorp/helm"
      version = "3.1.1"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "3.1.0"
    }
    tls = {
      source  = "hashicorp/tls"
      version = "4.2.1"
    }
    harvester = {
      source  = "harvester/harvester"
      version = "1.8.0"
    }
    netbird = {
      source  = "netbirdio/netbird"
      version = "0.0.9"
    }
  }
}

provider "onepassword" {
  service_account_token = var.op_service_account_token
}


provider "cloudflare" {
  api_token = data.onepassword_item.cloudflare.credential
}

provider "digitalocean" {
  token = data.onepassword_item.digitalocean.credential
}

provider "netbird" {
  token = data.onepassword_item.netbird.credential
}
