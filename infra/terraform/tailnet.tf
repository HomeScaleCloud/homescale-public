resource "tailscale_acl" "acl" {
  acl = <<EOF
    // This tailnet's ACLs are maintained in https://github.com/HomeScaleCloud/homescale
    {
      "acls": [
        {
          "action": "accept",
          "src": ["autogroup:member"],
          "dst": ["tag:app:*"]
        },
        {
          "action": "accept",
          "src": ["autogroup:member"],
          "dst": ["autogroup:self:*"]
        },
        {
          "action": "accept",
          "src": ["tag:github-actions"],
          "dst": ["tag:app:443"]
        },
        {
          "action": "accept",
          "src": [
            "group:Kubernetes Viewers@homescale.cloud",
            "group:Kubernetes Admins@homescale.cloud"
          ],
          "dst": ["tag:k8s-api:443"]
        }
      ],
      "tagOwners": {
        "tag:k8s-operator": ["tag:k8s-operator"],
        "tag:k8s-api": ["tag:k8s-operator"],
        "tag:app": ["tag:k8s-operator"],
        "tag:github-actions": []
      },
      "nodeAttrs": [
        {
          "target": ["autogroup:member"],
          "attr": ["mullvad"]
        }
      ],
      "grants": [
        {
          "src": ["group:Kubernetes Viewers@homescale.cloud"],
          "dst": ["tag:k8s-api"],
          "app": {
            "tailscale.com/cap/kubernetes": [
              {
                "impersonate": {
                  "groups": ["kubernetes-viewers"]
                }
              }
            ]
          }
        },
        {
          "src": ["group:Kubernetes Admins@homescale.cloud"],
          "dst": ["tag:k8s-api"],
          "app": {
            "tailscale.com/cap/kubernetes": [
              {
                "impersonate": {
                  "groups": ["system:masters"]
                }
              }
            ]
          }
        },
      ],
      "ssh": [
        {
          "action": "check",
          "src":    ["autogroup:member"],
          "dst":    ["autogroup:self"],
          "users":  ["autogroup:nonroot", "root"],
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

resource "tailscale_webhook" "slack" {
  endpoint_url  = data.onepassword_item.tailscale_slack.password
  provider_type = "slack"
  subscriptions = ["exitNodeIPForwardingNotEnabled", "subnetIPForwardingNotEnabled", "policyUpdate", "userCreated", "userRoleUpdated"]
}

resource "tailscale_oauth_client" "k8s_core" {
  description = "k8s-core"
  scopes      = ["devices:core", "auth_keys"]
  tags        = ["tag:k8s-operator", "tag:app", "tag:k8s-api"]
}

resource "tailscale_oauth_client" "k8s_manor" {
  description = "k8s-manor"
  scopes      = ["devices:core", "auth_keys"]
  tags        = ["tag:k8s-operator", "tag:app", "tag:k8s-api"]
}
