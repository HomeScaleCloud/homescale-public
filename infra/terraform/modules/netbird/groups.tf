data "netbird_group" "all" {
  name = "All"
}

resource "netbird_group" "github_actions" {
  name = "GitHub Actions"
}

resource "netbird_group" "env_mgmt" {
  name = "env-mgmt"
}

resource "netbird_group" "env_prod" {
  name = "env-prod"
}

resource "netbird_group" "env_lab" {
  name = "env-lab"
}

locals {
  app_names = sort(distinct([
    for app_file in fileset("${path.module}/../../../apps", "*/**") : split("/", app_file)[0]
  ]))
}

resource "netbird_group" "app" {
  for_each = toset(local.app_names)

  name = "app-${each.key}"
}
