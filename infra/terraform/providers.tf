terraform {
  required_providers {
    onepassword = {
      source  = "1Password/onepassword"
      version = "2.2.1"
    }
    cloudflare = {
      source  = "cloudflare/cloudflare"
      version = "5.18.0"
    }
    digitalocean = {
      source  = "digitalocean/digitalocean"
      version = "2.81.0"
    }
    rancher2 = {
      source  = "rancher/rancher2"
      version = "8.5.0"
    }
    helm = {
      source  = "hashicorp/helm"
      version = "3.1.1"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "3.0.1"
    }
    twingate = {
      source  = "Twingate/twingate"
      version = "4.0.2"
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

provider "twingate" {
  api_token = data.onepassword_item.twingate.credential
  network   = "homescale"
}
