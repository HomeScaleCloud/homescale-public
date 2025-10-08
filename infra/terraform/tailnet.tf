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
            "group:team-k8s-infra@homescale.cloud",
            "group:sg-k8s-infra-admin@homescale.cloud"
          ],
          "dst": ["tag:k8s-api:443"]
        },
        {
          "action": "accept",
          "src": [
            "group:sg-k8s-infra-admin@homescale.cloud",
            "tag:github-actions"
          ],
          "dst": ["tag:node:22"]
        }
      ],
      "tagOwners": {
        "tag:k8s-operator": ["tag:k8s-operator"],
        "tag:k8s-api": ["tag:k8s-operator"],
        "tag:app": ["tag:k8s-operator"],
        "tag:node": [],
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
          "src": ["group:team-k8s-infra@homescale.cloud"],
          "dst": ["tag:k8s-api"],
          "app": {
            "tailscale.com/cap/kubernetes": [
              {
                "impersonate": {
                  "groups": ["team-k8s-infra"]
                }
              }
            ]
          }
        },
        {
          "src": ["group:sg-k8s-infra-admin@homescale.cloud"],
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
          "users":  ["autogroup:nonroot"],
        },
        {
          "action": "check",
          "checkPeriod": "2h",
          "src": ["group:sg-k8s-infra-admin@homescale.cloud"],
          "dst": ["tag:node"],
          "users": ["admin"],
        },
        {
          "action": "accept",
          "src": ["tag:github-actions"],
          "dst": ["tag:node"],
          "users": ["admin"],
        },
      ],
    }
  EOF
}

resource "tailscale_tailnet_settings" "settings" {
  devices_auto_updates_on        = true
  devices_key_duration_days      = 35
  posture_identity_collection_on = true
  devices_approval_on            = true
  acls_externally_managed_on     = true
  acls_external_link             = "https://github.com/HomeScaleCloud/homescale"
}

resource "tailscale_webhook" "slack" {
  endpoint_url  = data.onepassword_item.tailscale_slack.password
  provider_type = "slack"
  subscriptions = ["exitNodeIPForwardingNotEnabled", "subnetIPForwardingNotEnabled", "policyUpdate", "userCreated", "userRoleUpdated"]
}

resource "tailscale_tailnet_key" "node_key" {
  reusable            = true
  preauthorized       = true
  recreate_if_invalid = "always"
  description         = "Node key"
  tags                = ["tag:node"]
}
