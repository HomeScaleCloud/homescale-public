#!/usr/bin/env bash
# Syncs cluster templates and machine classes into Omni via omnictl.
#
# args (ARGS_JSON): clusters/machineclasses, each a comma-separated list of names. Key
# absent means "everything" (the default/merge-time behavior); key present but empty means
# "none" — deploy.yaml's PR-time plan step needs that distinction (e.g. only a machineclass
# changed, zero clusters to plan).
#
# Prints "=== BEGIN/END <KIND> <name> ===" around each item's output so a caller reading
# the combined pod log can split it back into per-item results (see deploy.yaml).
set -euo pipefail

export OMNI_ENDPOINT="${OMNI_ENDPOINT:-https://REDACTED}"
repo_root="${REPO_DIR:-.}"
[[ -z "${ARGS_JSON:-}" ]] && ARGS_JSON="{}"

dry_run_flag=""
[[ "${DRY_RUN:-false}" == "true" ]] && dry_run_flag="--dry-run"

clusters=()
if jq -e 'has("clusters")' <<<"$ARGS_JSON" >/dev/null; then
    IFS=',' read -r -a clusters <<< "$(jq -r '.clusters' <<<"$ARGS_JSON")"
else
    while read -r d; do clusters+=("$(basename "$d")"); done \
        < <(find "$repo_root/clusters" -mindepth 2 -maxdepth 2 -name cluster.yaml | xargs -n1 dirname | sort -u)
fi

machineclasses=()
if jq -e 'has("machineclasses")' <<<"$ARGS_JSON" >/dev/null; then
    IFS=',' read -r -a machineclasses <<< "$(jq -r '.machineclasses' <<<"$ARGS_JSON")"
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
