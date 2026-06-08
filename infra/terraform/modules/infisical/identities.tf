resource "infisical_identity" "k8s_mgmt_operator" {
  name   = "k8s-mgmt-operator"
  org_id = var.org_id
  role   = "no-access"
}

resource "infisical_identity_universal_auth" "k8s_mgmt_operator" {
  identity_id          = infisical_identity.k8s_mgmt_operator.id
  access_token_ttl     = 3600
  access_token_max_ttl = 86400
  access_token_trusted_ips = [
    { ip_address = "0.0.0.0/0" },
    { ip_address = "::/0" },
  ]
}

resource "infisical_identity_universal_auth_client_secret" "k8s_mgmt_operator" {
  identity_id = infisical_identity.k8s_mgmt_operator.id
}

resource "infisical_project_identity" "k8s_mgmt_operator" {
  project_id  = infisical_project.homescale.id
  identity_id = infisical_identity.k8s_mgmt_operator.id
  roles = [{
    role_slug    = "viewer"
    is_temporary = false
  }]
}
