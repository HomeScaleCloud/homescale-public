terraform {
  required_providers {
    netbird = {
      source = "netbirdio/netbird"
    }
    onepassword = {
      source = "1Password/onepassword"
    }
  }
}

provider "netbird" {
  token = var.netbird_token
}

provider "onepassword" {
  service_account_token = var.op_service_account_token
}
