terraform {
  required_providers {
    onepassword = {
      source = "1Password/onepassword"
    }
    netbird = {
      source = "netbirdio/netbird"
    }
    rancher2 = {
      source = "rancher/rancher2"
    }
  }
}

provider "onepassword" {
  service_account_token = var.op_service_account_token
}

provider "netbird" {
  token = var.netbird_token
}

provider "rancher2" {
  api_url   = "https://REDACTED"
  token_key = data.onepassword_item.rancher_token.password
}
