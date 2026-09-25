#!/usr/bin/env bash
# Render every app catalog and per-app chart the way ArgoCD would — once per
# cluster in clusters/ — and schema-validate the output with kubeconform.
#
# CRD coverage: kubeconform gets the Kubernetes schemas plus the
# datreeio/CRDs-catalog, with -ignore-missing-schemas. A *skipped* resource
# whose kind isn't in NO_SCHEMA_OK is still a hard failure, so an unschematized
# CR can't slip through silently — add it to NO_SCHEMA_OK or wire up a
# -schema-location.
#
# Usage: .github/scripts/validate-manifests.sh
# Env:   KUBERNETES_VERSION (default 1.34.0)
#
# Needs kubeconform 0.7.x — 0.8.0 regressed `-verbose -output json` and `-skip`.
# CI pins 0.7.0 in scan.yaml.

set -euo pipefail

KUBERNETES_VERSION="${KUBERNETES_VERSION:-1.34.0}"
CRD_CATALOG='https://raw.githubusercontent.com/datreeio/CRDs-catalog/main/{{.Group}}/{{.ResourceKind}}_{{.ResourceAPIVersion}}.json'

# Kinds allowed to have no schema: CustomResourceDefinition (kubeconform ships
# none), the slinky.slurm.net CRs from apps/slurm — too new/niche for
# datreeio's CRDs-catalog — and REDACTED's kro-generated CRDs
# (repo-local, will never appear in a public catalog).
NO_SCHEMA_OK=(CustomResourceDefinition Controller NodeSet RestApi Accounting LoginSet JobTemplate JobRun JobWorkflow JobWorkflowRun)

# Kinds whose catalog schema is known wrong for the chart version we pin (revisit
# on bump). ImageUpdater: datreeio's schema marks fields required that
# argocd-image-updater 1.3.1's actual CRD doesn't. ResourceGraphDefinition:
# datreeio's schema is stale for kro 0.9.4 — missing spec.schema.scope (and
# shortNames/categories), and sets additionalProperties: false so it hard-rejects them.
KNOWN_BAD_SCHEMA=(ImageUpdater ResourceGraphDefinition)

repo_root="$(git rev-parse --show-toplevel)"
cd "$repo_root"

for bin in helm yq kubeconform; do
    command -v "$bin" >/dev/null || { echo "validate-manifests.sh: '$bin' is required" >&2; exit 1; }
done

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
fail=0

group()    { if [[ -n "${GITHUB_ACTIONS:-}" ]]; then echo "::group::$*"; else echo "==> $*"; fi; }
endgroup() { if [[ -n "${GITHUB_ACTIONS:-}" ]]; then echo "::endgroup::"; fi; }
error()    { if [[ -n "${GITHUB_ACTIONS:-}" ]]; then echo "::error::$*"; else echo "ERROR: $*" >&2; fi; }

in_list() { local x="$1"; shift; printf '%s\n' "$@" | grep -qxF "$x"; }

# conform <label> <rendered-manifest-file> [strict]
# Schema-check one rendered stream. Returns non-zero (and prints) on any invalid
# or errored resource, or any skipped resource whose kind is not allowlisted.
conform() {
    local label="$1" file="$2" strict="${3:-}"
    local json="$tmp/kc.json" rc=0
    kubeconform -kubernetes-version "$KUBERNETES_VERSION" \
        -schema-location default -schema-location "$CRD_CATALOG" \
        -ignore-missing-schemas -verbose -output json ${strict:+-strict} \
        <"$file" >"$json" 2>"$tmp/kcerr" || true
    if [[ ! -s "$json" ]]; then
        error "$label: kubeconform produced no output"
        cat "$tmp/kcerr" >&2
        return 1
    fi

    # invalid / errored resources — one compact JSON object per line
    local line kind
    local -a known_bad=()
    while IFS= read -r line; do
        [[ -z "$line" ]] && continue
        kind="$(yq -p=json -o=yaml '.kind' <<<"$line")"
        if in_list "$kind" "${KNOWN_BAD_SCHEMA[@]}"; then
            known_bad+=("$(yq -p=json -o=yaml '.kind + "/" + .name' <<<"$line")")
            continue
        fi
        error "$label: invalid resource"
        yq -p=json -o=yaml '"    " + .kind + "/" + .name + ": " + (.msg // "" | sub("\n"; " "))' <<<"$line" >&2
        rc=1
    done < <(yq -p=json -o=json -I=0 \
        '.resources[] | select(.status == "statusInvalid" or .status == "statusError")' "$json")

    # resources kubeconform had no schema for — a hard failure unless the kind is
    # allowlisted, so a newly-added CR with no schema anywhere cannot slip through
    while IFS= read -r kind; do
        [[ -z "$kind" ]] && continue
        in_list "$kind" "${NO_SCHEMA_OK[@]}" "${KNOWN_BAD_SCHEMA[@]}" && continue
        error "$label: no schema for '$kind' (resource skipped) — add a -schema-location or list it in NO_SCHEMA_OK"
        rc=1
    done < <(yq -p=json -o=yaml -I=0 \
        '.resources[] | select(.status == "statusSkipped") | .kind' "$json" | sort -u)

    local n_valid n_skip summary known_bad_joined
    n_valid="$(yq -p=json -o=yaml '[.resources[] | select(.status == "statusValid")] | length' "$json")"
    n_skip="$(yq -p=json -o=yaml '[.resources[] | select(.status == "statusSkipped")] | length' "$json")"
    summary="   $label: ${n_valid} valid, ${n_skip} skipped (allowlisted CRD objects)"
    if ((${#known_bad[@]})); then
        known_bad_joined="$(printf '%s, ' "${known_bad[@]}")"
        summary+=", ${#known_bad[@]} known-bad-schema ignored (${known_bad_joined%, })"
    fi
    echo "$summary"
    return $rc
}

group "helm dependency build"
for chart in apps/*/Chart.yaml; do
    dir="$(dirname "$chart")"
    grep -q '^dependencies:' "$chart" || continue
    echo "-> $dir"
    helm dependency build "$dir" >/dev/null 2>&1 || helm dependency update "$dir" >/dev/null
done
endgroup

shopt -s nullglob
for cluster_dir in clusters/*/; do
    cluster="$(basename "$cluster_dir")"
    apps_yaml="${cluster_dir}apps.yaml"
    [[ -f "$apps_yaml" ]] || continue

    group "cluster: $cluster"

    apps_values="$(yq e '.spec.sources[] | select(.path == "apps") | .helm.values' "$apps_yaml")"
    if [[ -z "$apps_values" || "$apps_values" == "null" ]]; then
        error "$apps_yaml: no 'apps' source with helm.values found"
        fail=1; endgroup; continue
    fi

    bootstrap_name="$(yq e '.metadata.name' "$apps_yaml")"

    # Raw `directory` sources (clusters/<cluster>/ itself, and anything else synced
    # straight from git with no Helm rendering, e.g. infra/automatron/'s job/workflow
    # CRs) aren't covered by the catalog/per-app render below, so conform them directly —
    # every *.yaml/*.yml under the source path, minus its own `directory.exclude` file.
    # Scans every Application-kind manifest directly under clusters/<cluster>/, not just
    # apps.yaml — a directory-synced CR tree may deliberately live in its own independently
    # -synced Application instead of as another source on apps.yaml's (e.g. so a CRD-not-
    # -registered-yet retry on that tree can't block apps.yaml's own multi-source sync).
    for app_manifest in "$cluster_dir"*.yaml; do
        [[ "$(yq e '.kind' "$app_manifest")" == "Application" ]] || continue
        while IFS= read -r dir_path; do
            [[ -n "$dir_path" && -d "$dir_path" ]] || continue
            exclude="$(yq e "(.spec.sources // [.spec.source])[] | select(.path == \"$dir_path\") | .directory.exclude // \"\"" "$app_manifest")"
            raw="$tmp/$cluster-$(echo "$dir_path" | tr '/' '-').yaml"
            : > "$raw"
            while IFS= read -r -d '' f; do
                [[ -n "$exclude" && "$(basename "$f")" == "$exclude" ]] && continue
                cat "$f" >> "$raw"
                echo -e "\n---" >> "$raw"
            done < <(find "$dir_path" -type f \( -name '*.yaml' -o -name '*.yml' \) -print0 | sort -z)
            [[ -s "$raw" ]] && { conform "$dir_path ($cluster)" "$raw" || fail=1; }
        done < <(yq e -N '(.spec.sources // [.spec.source])[] | select(has("directory")) | .path' "$app_manifest")
    done

    catalog="$tmp/$cluster-catalog.yaml"
    if ! helm template apps apps/ -f - <<<"$apps_values" >"$catalog" 2>"$tmp/err"; then
        error "$apps_yaml: app catalog render failed for $cluster"
        cat "$tmp/err" >&2
        fail=1; endgroup; continue
    fi

    conform "$bootstrap_name ($cluster)" "$catalog" strict || fail=1

    while IFS= read -r app; do
        [[ -n "$app" && -d "apps/$app" ]] || continue
        values="$(yq e "select(.kind == \"Application\" and .metadata.labels.\"REDACTED/name\" == \"$app\") | .spec.source.helm.valuesObject // .spec.sources[0].helm.valuesObject" "$catalog")"
        rendered="$tmp/$cluster-$app.yaml"
        if ! helm template "$app" "apps/$app/" -f - <<<"$values" >"$rendered" 2>"$tmp/err"; then
            error "apps/$app: chart render failed for '$app' on $cluster"
            cat "$tmp/err" >&2
            fail=1; continue
        fi
        conform "$app ($cluster)" "$rendered" || fail=1
    done < <(yq e -N 'select(.kind == "Application") | .metadata.labels."REDACTED/name"' "$catalog")

    endgroup
done

if [[ "$fail" -ne 0 ]]; then
    echo "validate-manifests.sh: FAILED" >&2
    exit 1
fi
echo "validate-manifests.sh: OK"
