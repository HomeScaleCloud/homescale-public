resource "tailscale_acl" "acl" {
  acl = <<EOF
    // This tailnet's ACLs are maintained in https://github.com/HomeScaleCloud/homescale
    {
      "acls": [
        // Default ACLs
        {
          "action": "accept",
          "src": ["autogroup:member"],
          "dst": ["tag:app:443"]
        },
        {
          "action": "accept",
          "src": ["autogroup:member"],
          "dst": ["autogroup:self:*"]
        },

        // Apps
        // argocd
        {
          "action": "accept",
          "src": [
            "group:team-infra-plat@homescale.cloud",
            "tag:github-actions"
          ],
          "dst": ["tag:app-argocd:443"]
        },
        // ha
        {
          "action": "accept",
          "src": ["group:Owners@homescale.cloud"],
          "dst": ["tag:app-ha:443"]
        },
        // metrics
        {
          "action": "accept",
          "src": ["group:team-infra-plat@homescale.cloud"],
          "dst": ["tag:app-metrics:443"]
        },

        // Clusters + Nodes
        {
          "action": "accept",
          "src": [
            "group:team-infra-plat@homescale.cloud",
            "group:sec-infra-plat-pim@homescale.cloud"
          ],
          "dst": ["tag:k8s:443"]
        },
        {
          "action": "accept",
          "src": [
            "group:sec-infra-plat-pim@homescale.cloud",
            "tag:github-actions"
          ],
          "dst": ["tag:node:22,50000,50001,6443,5252","10.1.245.0/24:22,50000,50001,6443,5252"]
        }
      ],

      "grants": [
        {
          "src": ["group:team-infra-plat@homescale.cloud"],
          "dst": ["tag:k8s"],
          "app": {
            "tailscale.com/cap/kubernetes": [
              {
                "impersonate": {
                  "groups": ["team-infra-plat"]
                }
              }
            ]
          }
        },
        {
          "src": [
            "group:sec-infra-plat-pim@homescale.cloud",
            "tag:github-actions"
          ],
          "dst": ["tag:k8s"],
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
          "src": ["group:sec-infra-plat-pim@homescale.cloud"],
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

      "tagOwners": {
        "tag:k8s": ["tag:k8s"],
        "tag:app": ["tag:k8s"],

        "tag:app-argocd": ["tag:k8s"],
        "tag:app-ha": ["tag:k8s"],
        "tag:app-metrics": ["tag:k8s"],

        "tag:node": [],
        "tag:github-actions": [],

        "tag:region-boa1": ["tag:k8s"],
        "tag:cluster-atlas": ["tag:k8s"]
      },

      "nodeAttrs": [
        {
          "target": ["autogroup:member"],
          "attr": ["mullvad"]
        }
      ],

      "autoApprovers": {
          "services": {
              "tag:k8s": ["tag:k8s"],
          },
      }
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
  subscriptions = ["exitNodeIPForwardingNotEnabled", "subnetIPForwardingNotEnabled", "policyUpdate", "userCreated", "userRoleUpdated", "nodeNeedsApproval"]
}

resource "tailscale_tailnet_key" "node_key" {
  reusable            = true
  preauthorized       = true
  recreate_if_invalid = "always"
  description         = "Node key"
  tags                = ["tag:node"]
}
