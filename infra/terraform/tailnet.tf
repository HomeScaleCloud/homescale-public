resource "tailscale_acl" "acl" {
  acl = <<EOF
    // This tailnet's ACLs are maintained in https://github.com/HomeScaleCloud/homescale
    {
      "grants": [
        // =========================
        // Defaults
        // =========================
        {
          "src": ["autogroup:member"],
          "dst": ["tag:app"], // <-- Untagged Apps
          "ip": ["*"]
        },
        {
          "src": ["autogroup:member"],
          "dst": ["tag:env-lab"],
          "ip": ["*"]
        },
        {
          "src": ["autogroup:member"],
          "dst": ["autogroup:self"],
          "ip": ["*"]
        },

        // =========================
        // Apps
        // =========================
        // rancher
        {
          "src": [
            "group:team-infra-plat@homescale.cloud",
            "group:team-sec-plat@homescale.cloud"
          ],
          "dst": ["tag:app-rancher"],
          "ip": ["tcp:443"]
        },

        // ha
        {
          "src": ["group:Owners@homescale.cloud"],
          "dst": ["tag:app-ha"],
          "ip": ["tcp:443"]
        },

        // metrics
        {
          "src": [
            "group:team-infra-plat@homescale.cloud",
            "group:team-sec-plat@homescale.cloud",
            "rainmitch.personal@outlook.com"
          ],
          "dst": ["tag:app-metrics"],
          "ip": ["tcp:443"]
        },

        // =========================
        // Clusters + Nodes
        // =========================
        // Kubernetes
        {
          "src": [
            "group:team-infra-plat@homescale.cloud",
            "group:sec-infra-plat-pim@homescale.cloud"
          ],
          "dst": ["tag:k8s"],
          "ip": ["tcp:443"],
          "app": {
            "tailscale.com/cap/kubernetes": [
              { "impersonate": { "groups": ["team-infra-plat"] } }
            ]
          }
        },
        {
          "src": [
            "group:sec-infra-plat-pim@homescale.cloud",
            "tag:github-actions"
          ],
          "dst": ["tag:k8s"],
          "ip": ["tcp:443"],
          "app": {
            "tailscale.com/cap/kubernetes": [
              { "impersonate": { "groups": ["system:masters"] } }
            ]
          }
        },
        {
          "src": ["autogroup:member"],
          "dst": ["tag:env-lab"],
          "ip": ["tcp:443"],
          "app": {
            "tailscale.com/cap/kubernetes": [
              { "impersonate": { "groups": ["system:masters"] } }
            ]
          }
        },

        // Nodes
        {
          "src": [
            "group:sec-infra-plat-pim@homescale.cloud",
            "tag:github-actions"
          ],
          "dst": ["tag:node", "10.1.245.0/24"],
          "ip": ["tcp:22", "tcp:50000-50001", "tcp:8006", "tcp:6443", "tcp:5252"]
        }
      ],

      // ==========
      // SSH
      // ==========
      "ssh": [
        {
          "action": "check",
          "src": ["autogroup:member"],
          "dst": ["autogroup:self"],
          "users": ["autogroup:nonroot"]
        },
        {
          "action": "accept",
          "src": ["autogroup:member"],
          "dst": ["tag:env-lab"],
          "users": ["autogroup:nonroot"]
        },
        {
          "action": "check",
          "checkPeriod": "2h",
          "src": ["group:sec-infra-plat-pim@homescale.cloud"],
          "dst": ["tag:node"],
          "users": ["hs"]
        },
        {
          "action": "accept",
          "src": ["tag:github-actions"],
          "dst": ["tag:node"],
          "users": ["hs"]
        }
      ],

      // =========
      // Tags
      // =========
      "tagOwners": {
        "tag:k8s": ["tag:k8s"],
        "tag:app": ["tag:k8s"],

        "tag:app-ha":      ["tag:k8s"],
        "tag:app-metrics": ["tag:k8s"],
        "tag:app-rancher": ["tag:k8s"],

        "tag:node":          [],
        "tag:github-actions": [],
        "tag:tv":            [],

        "tag:env-mgmt": ["tag:k8s"],
        "tag:env-prod": ["tag:k8s"],
        "tag:env-test": ["tag:k8s"],
        "tag:env-lab":  ["tag:k8s"],

        "tag:lf-k8s-lab": []
      },

      // ======================
      // Node attributes
      // ======================
      "nodeAttrs": [
        { "target": ["autogroup:member"], "attr": ["mullvad"] },
        { "target": ["tag:tv"], "attr": ["mullvad"] }
      ],

      // ===========================
      // Tailscale Approvals
      // ===========================
      "autoApprovers": {
        "services": {
          "tag:k8s": ["tag:k8s"],
          "tag:app": ["tag:app"],
          "tag:app-ha": ["tag:app"],
          "tag:app-metrics": ["tag:app"],
          "tag:app-rancher": ["tag:app"]
        }
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
