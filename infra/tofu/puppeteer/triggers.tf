locals {
  # One entry per (module, dependency) edge declared in that module's terrakube.yaml
  # dependsOn list — becomes "runs after" in Terrakube.
  run_trigger_edges = {
    for edge in flatten([
      for name, mod in local.terrakube_modules : [
        for dep in try(mod.dependsOn, []) : {
          key    = "${dep}-${name}"
          source = dep
          dest   = name
        }
      ]
    ]) : edge.key => edge
  }
}

resource "terrakube_workspace_run_trigger" "deps" {
  for_each = local.run_trigger_edges

  source_workspace_id      = terrakube_workspace_vcs.module[each.value.source].id
  destination_workspace_id = terrakube_workspace_vcs.module[each.value.dest].id
}
