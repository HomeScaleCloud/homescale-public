terraform {
  required_providers {
    onepassword = {
      source = "1Password/onepassword"
    }
  }
}

provider "onepassword" {
  service_account_token = var.op_service_account_token
}
