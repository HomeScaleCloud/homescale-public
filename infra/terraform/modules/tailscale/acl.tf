# Mirrors modules/netbird/policies.tf's app.yaml-scanning mechanism, but
# Tailscale's ACL model is a single policy document (not many discrete
# policy objects), so every app's rules are flattened into one grants list
# feeding one tailscale_acl resource.

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

  # One entry per rule: single-rule apps use app_name, multi-rule apps use app_name-N
  app_policy_rules = merge([
    for app_name, policy in local.app_policies : {
      for idx, rule in policy.rules :
      length(policy.rules) == 1 ? app_name : "${app_name}-${idx}" => merge(rule, { app = app_name })
    }
  ]...)

  # Valid `sources:` vocabulary for an app's tailscale.policy block.
  source_tags = merge(
    { "all" = "*" },
    { "github-actions" = "tag:github-actions" },
    { for t in local.fixed_source_tags : t => "tag:${t}" },
    { for k in local.app_names : "app:${k}" => "tag:app-${k}" }
  )

  # tagOwners: who is allowed to apply each tag to a device.
  tag_owners = merge(
    {
      "tag:k8s-operator"   = ["autogroup:admin"]
      "tag:github-actions" = ["autogroup:admin"]
    },
    { for t in local.fixed_source_tags : "tag:${t}" => ["autogroup:admin"] },
    { for k in local.app_names : "tag:app-${k}" => ["tag:k8s-operator"] },
    { for k in local.cluster_names : "tag:cluster-${k}" => ["tag:k8s-operator"] },
  )

  # Every app's declared tailscale.policy rules, flattened into ACL grants.
  app_grants = [
    for key, rule in local.app_policy_rules : {
      src = [for s in rule.sources : local.source_tags[s]]
      dst = ["tag:app-${rule.app}"]
      ip  = [for p in try(rule.ports, []) : "${rule.protocol}:${p}"]
    }
  ]

  # Generic access to every cluster's Tailscale-exposed apiserver-proxy,
  # mirroring NetBird's hardcoded "Kubernetes" policy. NetBird's separate
  # region_mgmt/region_bmc/omni_k8s policies are intentionally not
  # replicated here -- they depend on gateway-cluster/region infra that
  # isn't built on the Tailscale side yet (modules/region/ is still
  # NetBird-only and untouched). Revisit at cutover time.
  k8s_grant = {
    src = ["tag:team-infra-plat", "tag:team-sec-plat", "tag:sg-k8s-admin", "tag:app-headlamp"]
    dst = [for k in local.cluster_names : "tag:cluster-${k}"]
    ip  = ["tcp:443"]
  }

  grants = concat(local.app_grants, [local.k8s_grant])
}

resource "tailscale_acl" "this" {
  acl = jsonencode({
    tagOwners = local.tag_owners
    grants    = local.grants
  })

  # The provider sets an ETag precondition that only lets Create() succeed if
  # the tailnet's ACL has never been changed from Tailscale's own internal
  # default -- otherwise it 412s. Terraform is meant to fully own this ACL
  # going forward, so that protection (meant for ACLs configured by hand
  # outside Terraform) doesn't apply to us.
  overwrite_existing_content = true
}
