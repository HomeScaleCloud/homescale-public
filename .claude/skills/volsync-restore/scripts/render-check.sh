#!/usr/bin/env bash
# volsync-restore skill helper — renders the actual merged manifests for one app
# on one cluster and reports replica counts plus ReplicationSource/Destination
# presence. Catches a typo'd or wrong values path (e.g. `replicaCount` when the
# chart reads `controller.replicaCount`) silently merging in and doing nothing.
#
# Usage: render-check.sh <cluster> <app>
set -euo pipefail

cluster="${1:-}"
app="${2:-}"
if [[ -z "$cluster" || -z "$app" ]]; then
    echo "Usage: render-check.sh <cluster> <app>" >&2
    exit 1
fi

repo_root="$(git rev-parse --show-toplevel 2>/dev/null || true)"
if [[ -z "$repo_root" ]]; then
    echo "render-check.sh: must be run from inside the homescale repo" >&2
    exit 1
fi
cd "$repo_root"

[[ -f "apps/$app/app.yaml" ]] || { echo "render-check.sh: no apps/$app/app.yaml" >&2; exit 1; }
[[ -f "clusters/$cluster/apps.yaml" ]] || { echo "render-check.sh: no clusters/$cluster/apps.yaml" >&2; exit 1; }

for bin in helm yq; do
    command -v "$bin" &>/dev/null || { echo "render-check.sh: '$bin' is required" >&2; exit 1; }
done

# The CLAUDE.md/docs `helm template apps ...` command only renders apps with
# `defaultDeploy: true`, missing anything enabled only via the per-cluster
# `apps:` override (the common case here). So render with the real embedded
# values block from the `apps` source instead.
apps_values=$(yq e '.spec.sources[] | select(.path == "apps") | .helm.values' "clusters/$cluster/apps.yaml")
if [[ -z "$apps_values" || "$apps_values" == "null" ]]; then
    echo "render-check.sh: couldn't find the 'apps' source in clusters/$cluster/apps.yaml" >&2
    exit 1
fi

if ! catalog_render=$(helm template apps apps/ -f - <<< "$apps_values" 2>&1); then
    if grep -q "larger than the maximum file size" <<< "$catalog_render"; then
        echo "render-check.sh: helm choked on an oversized file somewhere under apps/ (often a stray local node_modules/ from a plugin build)." >&2
        echo "  Find it with: find apps -type d -name node_modules; add an apps/.helmignore entry or remove it, then retry." >&2
    else
        echo "$catalog_render" >&2
    fi
    exit 1
fi

app_doc=$(yq e "select(.kind == \"Application\" and .metadata.name == \"$app\")" - <<< "$catalog_render")
if [[ -z "$app_doc" ]]; then
    echo "render-check.sh: app '$app' did not render an Application for cluster '$cluster' (not enabled there?)" >&2
    exit 1
fi

values=$(yq e '.spec.source.helm.valuesObject // .spec.sources[0].helm.valuesObject' - <<< "$app_doc")

app_render=$(helm template "$app" "apps/$app/" -f - <<< "$values")

echo "== Workload replica counts (apps/$app on $cluster) =="
workloads=$(yq e 'select(.kind == "Deployment" or .kind == "StatefulSet") | {"kind": .kind, "name": .metadata.name, "replicas": .spec.replicas}' - <<< "$app_render")
if [[ -z "$workloads" ]]; then
    echo "(no Deployment/StatefulSet rendered)"
else
    echo "$workloads"
fi

echo
echo "== VolSync objects (apps/$app on $cluster) =="
volsync_objs=$(yq e 'select(.kind == "ReplicationSource" or .kind == "ReplicationDestination") | {"kind": .kind, "name": .metadata.name}' - <<< "$app_render")
if [[ -z "$volsync_objs" ]]; then
    echo "(none rendered -- app has no templates/volsync.yaml, or nothing matched)"
else
    echo "$volsync_objs"
fi
