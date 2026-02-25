resource "tailscale_acl" "acl" {
  acl = <<EOF
    // This tailnet's ACLs are maintained in https://github.com/HomeScaleCloud/homescale
    {
      "acls": [
        // Default ACLs
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

        // Apps
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
        {
          "action": "accept",
          "src": ["rainmitch.personal@outlook.com"],
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
          "dst": ["tag:node:22,50000,50001,8006,6443,5252","10.1.245.0/24:22,50000,50001,8006,6443,5252"]
        },

        // LF K8s Lab
        {
          "action": "accept",
          "src": [
            "group:team-infra-plat@homescale.cloud",
            "popsbot1@gmail.com"
          ],
          "dst": ["tag:lf-k8s-lab:*"]
        },
        {
          "action": "accept",
          "src": ["tag:lf-k8s-lab"],
          "dst": ["tag:lf-k8s-lab:*"]
        },
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
          "users": ["hs"],
        },
        {
          "action": "accept",
          "src": ["tag:github-actions"],
          "dst": ["tag:node"],
          "users": ["hs"],
        },

        // LF K8s Lab
        {
          "action": "accept",
          "src": [
            "group:team-infra-plat@homescale.cloud",
            "popsbot1@gmail.com"
          ],
          "dst": ["tag:lf-k8s-lab"],
          "users": ["hs"],
        },
      ],

      "tagOwners": {
        "tag:k8s": ["tag:k8s"],
        "tag:app": ["tag:k8s"],

        "tag:app-ha": ["tag:k8s"],
        "tag:app-metrics": ["tag:k8s"],

        "tag:node": [],
        "tag:github-actions": [],
        "tag:tv": [],

        "tag:env-prod": ["tag:k8s"],
        "tag:env-test": ["tag:k8s"],
        "tag:env-lab": ["tag:k8s"],

        "tag:lf-k8s-lab": [],
      },

      "nodeAttrs": [
        {
          "target": ["autogroup:member"],
          "attr": ["mullvad"]
        },
        {
          "target": ["tag:tv"],
          "attr": ["mullvad"]
        }
      ],

      "autoApprovers": {
          "services": {
              "tag:k8s": ["tag:k8s"],
              "tag:app": ["tag:app"],
              "tag:app-ha": ["tag:app"],
              "tag:app-metrics": ["tag:app"],
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
