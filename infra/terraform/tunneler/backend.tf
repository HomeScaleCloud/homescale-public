terraform {
  cloud {
    hostname     = "REDACTED"
    organization = "HomeScale"

    workspaces {
      name = "tunneler"
    }
  }
}
