locals {
  app_yaml_files = fileset("${path.module}/../../../../apps", "*/app.yaml")

  app_yamls = {
    for f in local.app_yaml_files :
    split("/", f)[0] => yamldecode(file("${path.module}/../../../../apps/${f}"))
  }

  app_policies = {
    for name, y in local.app_yamls :
    name => y.tailscale.policy
    if try(y.tailscale.policy, null) != null
  }

  app_policy_rules = merge([
    for app_name, policy in local.app_policies : {
      for idx, rule in policy.rules :
      length(policy.rules) == 1 ? app_name : "${app_name}-${idx}" => merge(rule, { app = app_name })
    }
  ]...)

  tag_owners = merge(
    {
      "tag:k8s"            = ["autogroup:admin", "tag:k8s"]
      "tag:k8s-api"        = ["tag:k8s"]
      "tag:github-actions" = ["autogroup:admin"]
      "tag:tv"             = ["autogroup:admin"]
    },
    { for k in local.app_names : "tag:app-${k}" => ["tag:k8s"] },
    { for k in local.cluster_names : "tag:cluster-${k}" => ["tag:k8s"] },
  )

  app_grants = [
    for key, rule in local.app_policy_rules : {
      src = rule.sources
      dst = ["tag:app-${rule.app}"]
      ip  = [for p in try(rule.ports, []) : "${rule.protocol}:${p}"]
    }
  ]

  # tag:app-headlamp is deliberately NOT a source here: each Headlamp
  # instance now talks only to its own in-cluster apiserver (default
  # in-cluster serviceaccount, no Tailscale egress) instead of proxying to
  # every cluster's kube-apiserver-proxy, so it no longer needs this grant.
  k8s_grant = {
    src = ["group:team-infra-plat@REDACTED", "group:team-sec-plat@REDACTED", "group:sg-k8s-admin@REDACTED"]
    dst = ["tag:k8s-api"]
    ip  = ["tcp:443"]
  }

  self_grant = {
    src = ["autogroup:member"]
    dst = ["autogroup:self"]
    ip  = ["*"]
  }

  remote_control_grant = {
    src = ["group:team-infra-plat@REDACTED"]
    dst = ["*"]
    ip  = ["tcp:5252"]
    app = {
      "tailscale.com/cap/webui" = [
        {
          canEdit = ["*"]
        }
      ]
    }
  }

  grants = concat(local.app_grants, [local.k8s_grant, local.self_grant, local.remote_control_grant])

  node_attrs = [
    {
      target = ["autogroup:member"]
      attr   = ["mullvad"]
    },
    {
      target = ["tag:tv"]
      attr   = ["mullvad"]
    },
  ]
}

resource "tailscale_acl" "this" {
  acl = jsonencode({
    tagOwners = local.tag_owners
    grants    = local.grants
    nodeAttrs = local.node_attrs
    autoApprovers = {
      services = {
        "tag:k8s" = ["tag:k8s"]
      }
    }
  })

  # Without this, apply 412s once the ACL has been touched outside Terraform.
  overwrite_existing_content = true
}
