data "netbird_group" "all" {
  name = "All"
}

resource "netbird_group" "github_actions" {
  name = "GitHub Actions"
}

resource "netbird_group" "env_mgmt" {
  name = "REDACTED/mgmt"
}

resource "netbird_group" "env_prod" {
  name = "REDACTED/mgmt"
}

resource "netbird_group" "env_lab" {
  name = "REDACTED/lab"
}

locals {
  app_names = sort(distinct([
    for app_file in fileset("${path.module}/../../../apps", "*/**") : split("/", app_file)[0]
  ]))
}

resource "netbird_group" "app" {
  for_each = toset(local.app_names)

  name = "REDACTED/name=${each.key}"
}
