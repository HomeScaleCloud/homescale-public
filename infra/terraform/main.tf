module "cloudflare" {
  source                 = "./modules/cloudflare"
  infisical_workspace_id = module.infisical.project_id
}

module "infisical" {
  source = "./modules/infisical"
  org_id = var.infisical_org_id
}

module "tailscale" {
  source                 = "./modules/tailscale"
  infisical_workspace_id = module.infisical.project_id
}
