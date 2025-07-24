resource "tailscale_acl" "acl" {
  acl = <<EOF
    // This tailnet's ACLs are maintained in https://github.com/HomeScaleCloud/homescale
    {
        "acls": [
            {
                "action": "accept",
                "src":    ["autogroup:member"],
                "dst":    ["tag:app:*"],
            },
            {
                "action": "accept",
                "src":    ["autogroup:member"],
                "dst":    ["autogroup:self:*"],
            },
            {
                "action": "accept",
                "src":    ["tag:github-actions"],
                "dst": [
                    "tag:app:443",
                ],
            },
        ],
        "tagOwners": {
            "tag:k8s-operator":   [],
            "tag:app":            ["tag:k8s-operator"],
            "tag:github-actions": [],
        },
        "nodeAttrs": [
            {
                "target": ["autogroup:member"],
                "attr":   ["mullvad"],
            },
        ],
    }
  EOF
}

resource "tailscale_tailnet_settings" "settings" {
  devices_auto_updates_on                     = true
  devices_key_duration_days                   = 18
  posture_identity_collection_on              = true
  users_role_allowed_to_join_external_tailnet = "admin"
}

resource "tailscale_oauth_client" "operator_core" {
  description = "operator-core"
  scopes      = ["devices:core", "auth_keys"]
  tags        = ["tag:app", "tag:k8s-operator"]
}

resource "tailscale_oauth_client" "operator_manor" {
  description = "operator-manor"
  scopes      = ["devices:core", "auth_keys"]
  tags        = ["tag:app", "tag:k8s-operator"]
}
