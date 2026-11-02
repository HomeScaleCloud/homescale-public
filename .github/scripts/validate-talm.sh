#!/usr/bin/env bash
# Renders every clusters/<cluster>/ talm project's templates offline, to catch a broken
# values.yaml/template/patch before merge. Needs no real cluster secrets: generates one
# throwaway secrets.yaml in a scratch dir and points every render at it via --with-secrets,
# without ever touching (or needing --force on) the real, already-checked-out project dirs.
# Also checks that no two clusters share a podSubnets/serviceSubnets entry -- Tailscale
# can't route to two clusters claiming the same destination CIDR.
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
scratch="$(mktemp -d)"
trap 'rm -rf "$scratch"' EXIT

(cd "$scratch" && talm init -p generic -N throwaway --force >/dev/null 2>&1)
scratch_secrets="$scratch/secrets.yaml"

fail=0
for cluster_dir in "$repo_root"/clusters/*/; do
    cluster="$(basename "$cluster_dir")"
    [[ -f "$cluster_dir/Chart.yaml" ]] || continue

    for template in controlplane worker; do
        [[ -f "$cluster_dir/templates/$template.yaml" ]] || continue

        if [[ -d "$cluster_dir/values" ]]; then
            for values_file in "$cluster_dir"values/*.yaml; do
                [[ -f "$values_file" ]] || continue
                echo "rendering $cluster/$template with $(basename "$values_file")"
                if ! (cd "$cluster_dir" && talm template -t "templates/$template.yaml" --offline --values "values/$(basename "$values_file")" --with-secrets "$scratch_secrets" >/dev/null); then
                    echo "FAILED: $cluster/templates/$template.yaml with values/$(basename "$values_file")" >&2
                    fail=1
                fi
            done
        else
            echo "rendering $cluster/$template"
            if ! (cd "$cluster_dir" && talm template -t "templates/$template.yaml" --offline --with-secrets "$scratch_secrets" >/dev/null); then
                echo "FAILED: $cluster/templates/$template.yaml" >&2
                fail=1
            fi
        fi
    done
done

subnets_seen="$scratch/subnets-seen"
: > "$subnets_seen"
for cluster_dir in "$repo_root"/clusters/*/; do
    cluster="$(basename "$cluster_dir")"
    [[ -f "$cluster_dir/values.yaml" ]] || continue

    while IFS= read -r cidr; do
        [[ -z "$cidr" || "$cidr" == "null" ]] && continue
        echo "$cidr $cluster" >> "$subnets_seen"
    done < <(yq '(.podSubnets // [])[], (.serviceSubnets // [])[]' "$cluster_dir/values.yaml")
done

dupe_subnets="$(awk '{print $1}' "$subnets_seen" | sort | uniq -d)"
if [[ -n "$dupe_subnets" ]]; then
    while IFS= read -r cidr; do
        owners="$(awk -v c="$cidr" '$1 == c { printf "%s ", $2 }' "$subnets_seen")"
        echo "FAILED: $cidr is used by more than one cluster ($owners) -- podSubnets/serviceSubnets must be unique per cluster" >&2
    done <<< "$dupe_subnets"
    fail=1
fi

exit $fail
