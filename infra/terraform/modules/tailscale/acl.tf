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

  k8s_grant = {
    src = ["group:team-infra-plat@REDACTED", "group:team-sec-plat@REDACTED", "group:sg-k8s-admin@REDACTED", "tag:app-headlamp"]
    dst = ["tag:k8s-api"]
    ip  = ["tcp:443"]
  }

  self_grant = {
    src = ["autogroup:member"]
    dst = ["autogroup:self"]
    ip  = ["*"]
  }

  grants = concat(local.app_grants, [local.k8s_grant, local.self_grant])

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

  # Without this, Create() 412s unless the tailnet's ACL has never been
  # touched from Tailscale's own default -- Terraform is meant to fully own
  # this ACL, so that protection doesn't apply to us.
  overwrite_existing_content = true
}
