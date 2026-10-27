#!/usr/bin/env bash
# Syncs cluster templates and machine classes into Omni via omnictl. Used directly by CI
# (.github/workflows/deploy.yaml's omni job) and by `hsctl run omni-sync -e local`.
#
# Env vars:
#   CLUSTERS        - comma-separated cluster names to sync. Unset means "everything";
#                      set-but-empty means "none of these" — CI's PR-time plan needs that
#                      distinction (e.g. only a machine class changed, zero clusters to plan).
#   MACHINECLASSES   - same convention, for infra/omni/machineclasses/*.yaml
#   DRY_RUN          - "true" adds --dry-run to every omnictl call (default: "false")
#   REPO_DIR         - repo root (default: ".")
#   OMNI_ENDPOINT    - default: https://REDACTED
#
# Prints "=== BEGIN/END <KIND> <name> ===" around each item's output so a caller (CI's
# PR-comment step) can split the combined log back into per-item results.
set -euo pipefail

export OMNI_ENDPOINT="${OMNI_ENDPOINT:-https://REDACTED}"
repo_root="${REPO_DIR:-.}"

dry_run_flag=""
[[ "${DRY_RUN:-false}" == "true" ]] && dry_run_flag="--dry-run"

clusters=()
if [[ "${CLUSTERS+set}" == "set" ]]; then
    IFS=',' read -r -a clusters <<< "$CLUSTERS"
else
    while read -r d; do clusters+=("$(basename "$d")"); done \
        < <(find "$repo_root/clusters" -mindepth 2 -maxdepth 2 -name cluster.yaml | xargs -n1 dirname | sort -u)
fi

machineclasses=()
if [[ "${MACHINECLASSES+set}" == "set" ]]; then
    IFS=',' read -r -a machineclasses <<< "$MACHINECLASSES"
else
    while read -r f; do machineclasses+=("$(basename "$f" .yaml)"); done \
        < <(find "$repo_root/infra/omni/machineclasses" -maxdepth 1 -name '*.yaml' 2>/dev/null | sort -u)
fi

failed=false

for mc in "${machineclasses[@]:-}"; do
    [[ -z "$mc" ]] && continue
    echo "=== BEGIN MACHINECLASS $mc ==="
    omnictl apply -f "$repo_root/infra/omni/machineclasses/$mc.yaml" $dry_run_flag \
        && echo "=== END MACHINECLASS $mc OK ===" \
        || { echo "=== END MACHINECLASS $mc FAILED ==="; failed=true; }
done

for cluster in "${clusters[@]:-}"; do
    [[ -z "$cluster" ]] && continue
    echo "=== BEGIN CLUSTER $cluster ==="
    tmpdir=$(mktemp -d)
    CLUSTER_NAME="$cluster" envsubst '${CLUSTER_NAME}' < "$repo_root/clusters/$cluster/cluster.yaml" > "$tmpdir/cluster.yaml"
    mkdir -p "$tmpdir/patches"
    for pf in "$repo_root"/infra/omni/patches/*.yaml; do
        [[ -f "$pf" ]] && CLUSTER_NAME="$cluster" envsubst '${CLUSTER_NAME}' < "$pf" > "$tmpdir/patches/$(basename "$pf")"
    done
    omnictl cluster template sync -f "$tmpdir/cluster.yaml" $dry_run_flag \
        && echo "=== END CLUSTER $cluster OK ===" \
        || { echo "=== END CLUSTER $cluster FAILED ==="; failed=true; }
    rm -rf "$tmpdir"
done

[[ "$failed" == "false" ]]
