#!/usr/bin/env bash
# hsctl switch — fuzzy-switch kubeconfig context (local + live NetBird clusters)

switch_main() {
    [[ $# -gt 0 ]] && { echo "Usage: hsctl switch"; exit 1; }

    command -v fzf &>/dev/null || { echo "hsctl switch: fzf is required (brew install fzf)" >&2; exit 1; }

    # shellcheck source=/dev/null
    source "$HSCTL_ROOT/hsctl.d/get.sh"

    local local_ctx_names
    local_ctx_names=$(kubectl config get-contexts -o name 2>/dev/null || true)

    # Format: "tag\tname" — fzf shows only name (--with-nth=2), tag used for dispatch
    local lines=()

    while IFS= read -r ctx; do
        [[ -z "$ctx" ]] && continue
        lines+=("local	$ctx")
    done <<< "$local_ctx_names"

    local live_names
    live_names=$(HSCTL_OUTPUT=json get_clusters 2>/dev/null | \
        python3 -c "import json, sys; print('\n'.join(c['name'] for c in json.load(sys.stdin)))" 2>/dev/null || true)

    while IFS= read -r cluster; do
        [[ -z "$cluster" ]] && continue
        grep -qx "$cluster" <<< "$local_ctx_names" && continue
        lines+=("new	$cluster")
    done <<< "$live_names"

    [[ ${#lines[@]} -eq 0 ]] && { echo "hsctl switch: no contexts or clusters found" >&2; exit 1; }

    local selected
    selected=$(printf '%s\n' "${lines[@]}" | fzf \
        --delimiter=$'\t' \
        --with-nth=2 \
        --height=40% \
        --reverse \
        --no-sort) || exit 0

    [[ -z "$selected" ]] && exit 0

    local tag name
    tag=$(cut -f1 <<< "$selected")
    name=$(cut -f2 <<< "$selected")

    if [[ "$tag" == new ]]; then
        get_kubeconfig "$name" >/dev/null
    else
        kubectl config use-context "$name" >/dev/null
    fi

    kubectl ns || true
}
