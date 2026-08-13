# Parallel-build note: this module stands alongside modules/netbird (untouched)
# while both systems run side by side. It replicates the same app/cluster
# discovery mechanism modules/netbird/groups.tf uses, but Tailscale has no
# resource type for a "group" the way NetBird does -- device tags referenced
# directly in the ACL's tagOwners/grants take their place instead.

locals {
  app_names = sort(distinct([
    for app_file in fileset("${path.module}/../../../../apps", "*/**") : split("/", app_file)[0]
  ]))

  cluster_names = sort(distinct([
    for cluster_file in fileset("${path.module}/../../../../clusters", "*/**") : split("/", cluster_file)[0]
  ]))

  # Tags standing in for NetBird's pre-existing, IdP-synced (not
  # Terraform-managed) groups of the same name -- team-infra-plat,
  # team-sec-plat, sg-k8s-admin, sg-ssh-admin, Owners. Tailscale doesn't have
  # a direct equivalent wired up yet, so these are tags applied manually to
  # approved devices in the admin console. Confirm at cutover time whether
  # true IdP-synced Tailscale groups should replace this.
  fixed_source_tags = [
    "team-infra-plat",
    "team-sec-plat",
    "sg-k8s-admin",
    "sg-ssh-admin",
    "owners",
  ]
}
