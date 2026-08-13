module "cloudflare" {
  source                 = "./modules/cloudflare"
  infisical_workspace_id = module.infisical.project_id
}

module "infisical" {
  source = "./modules/infisical"
  org_id = var.infisical_org_id
}

module "netbird" {
  source                 = "./modules/netbird"
  infisical_workspace_id = module.infisical.project_id
}

# Parallel build-alongside phase (see plan): stands up Tailscale ACLs/OAuth
# clients next to the still-untouched NetBird module above. Nothing here
# removes or depends on module.netbird.
module "tailscale" {
  source                 = "./modules/tailscale"
  infisical_workspace_id = module.infisical.project_id
}

module "mgmt_cluster" {
  source                 = "./modules/mgmt_cluster"
  vultr_api_key          = data.infisical_secrets.github_actions.secrets["VULTR_TOKEN"].value
  k8s_version            = "v1.36.1+3"
  region                 = "lhr"
  infisical_workspace_id = module.infisical.project_id
  oidc_issuer_url        = data.infisical_secrets.oidc.secrets["OIDC_ISSUER_URL"].value
  oidc_client_id         = data.infisical_secrets.oidc.secrets["OIDC_CLIENT_ID"].value
}

# module "region_boa1" {
#   source                 = "./modules/region"
#   region                 = "boa1"
#   infisical_workspace_id = module.infisical.project_id
#   netbird_token          = var.netbird_token
#   mgmt_cidr              = "10.1.245.0/24"
#   bmc_cidr               = "10.1.246.0/24"
# }
