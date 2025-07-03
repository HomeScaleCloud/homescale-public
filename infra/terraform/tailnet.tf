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
        "postures": {
            "posture:tsVersion": ["node:tsVersion >= '1.80.2'"],
            "posture:linux":     ["node:os == 'linux'"],
            "posture:macos":     ["node:os == 'macos'", "node:osVersion >= '15.3.2'"],
            "posture:windows":   ["node:os == 'windows'", "node:osVersion >= '10.0.26100.3476'"],
            "posture:ios":       ["node:os == 'ios'", "node:osVersion >= '18.3.2'"],
        },
        "defaultSrcPosture": [
            "posture:tsVersion",
            "posture:linux",
            "posture:macos",
            "posture:windows",
            "posture:ios",
        ],
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
  devices_approval_on                         = true
  devices_auto_updates_on                     = true
  devices_key_duration_days                   = 5
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
