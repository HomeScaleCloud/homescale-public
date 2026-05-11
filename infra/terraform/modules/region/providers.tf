terraform {
  required_providers {
    onepassword = {
      source = "1Password/onepassword"
    }
    netbird = {
      source = "netbirdio/netbird"
    }
  }
}

provider "onepassword" {
  service_account_token = var.op_service_account_token
}

provider "netbird" {
  token = var.netbird_token
}
