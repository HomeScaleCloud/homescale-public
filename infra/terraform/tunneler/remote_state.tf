data "terraform_remote_state" "tokenmaster" {
  backend = "remote"

  config = {
    hostname     = "REDACTED"
    organization = "HomeScale"
    workspaces = {
      name = "tokenmaster"
    }
  }
}

locals {
  infisical_workspace_id = data.terraform_remote_state.tokenmaster.outputs.project_id
}

data "infisical_secrets" "ci" {
  env_slug     = "prod"
  folder_path  = "/ci"
  workspace_id = local.infisical_workspace_id
}
