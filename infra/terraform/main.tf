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

module "core_cluster" {
  source                 = "./modules/core_cluster"
  vultr_api_key          = data.infisical_secrets.ci.secrets["VULTR_TOKEN"].value
  k8s_version            = "v1.37.1+1"
  region                 = "lhr"
  infisical_workspace_id = module.infisical.project_id
  oidc_issuer_url        = data.infisical_secrets.oidc.secrets["OIDC_ISSUER_URL"].value
  oidc_client_id         = data.infisical_secrets.oidc.secrets["OIDC_CLIENT_ID"].value
}
