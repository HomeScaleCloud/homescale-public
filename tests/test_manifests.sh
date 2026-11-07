#!/usr/bin/env bash
# Check file selection, then render and schema-validate each cluster's apps.
# Renovate excludes kubeconform 0.8.0: JSON output and -skip regressions.
set -euo pipefail

validate_manifests() (
    CRD_CATALOG='https://raw.githubusercontent.com/datreeio/CRDs-catalog/main/{{.Group}}/{{.ResourceKind}}_{{.ResourceAPIVersion}}.json'

    # CRDs and Slurm resources have no catalog schema.
    NO_SCHEMA_OK=(CustomResourceDefinition Controller NodeSet RestApi Accounting LoginSet)

    # The catalog ImageUpdater schema conflicts with our pinned CRD; revisit on upgrade.
    KNOWN_BAD_SCHEMA=(ImageUpdater)

    repo_root="$(git rev-parse --show-toplevel)"
    cd "$repo_root"

    for bin in helm yq kubeconform; do
        command -v "$bin" >/dev/null || { echo "test_manifests.sh: '$bin' is required" >&2; exit 1; }
    done

    tmp="$(mktemp -d)"
    trap 'rm -rf "$tmp"' EXIT
    fail=0

    group()    { if [[ -n "${GITHUB_ACTIONS:-}" ]]; then echo "::group::$*"; else echo "==> $*"; fi; }
    endgroup() { if [[ -n "${GITHUB_ACTIONS:-}" ]]; then echo "::endgroup::"; fi; }
    error()    { if [[ -n "${GITHUB_ACTIONS:-}" ]]; then echo "::error::$*"; else echo "ERROR: $*" >&2; fi; }

    in_list() { local x="$1"; shift; printf '%s\n' "$@" | grep -qxF "$x"; }

    # conform <label> <manifest-file> [strict]: reject invalid or unallowlisted resources.
    conform() {
        local label="$1" file="$2" strict="${3:-}"
        local json="$tmp/kc.json" rc=0
        kubeconform -kubernetes-version "$kubernetes_version" \
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

        # Reject missing schemas unless explicitly allowlisted.
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
        kubernetes_version="${KUBERNETES_VERSION:-$(yq '.kubernetesVersion' "${cluster_dir}topf.yaml")}"
        if [[ ! "$kubernetes_version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
            error "$cluster: declare kubernetesVersion in topf.yaml"
            fail=1
            continue
        fi

        group "cluster: $cluster"

        apps_values="$(yq e '.spec.sources[] | select(.path == "apps") | .helm.values' "$apps_yaml")"
        if [[ -z "$apps_values" || "$apps_values" == "null" ]]; then
            error "$apps_yaml: no 'apps' source with helm.values found"
            fail=1; endgroup; continue
        fi

        bootstrap_name="$(yq e '.metadata.name' "$apps_yaml")"
        short_name="$(yq e '.env.shortName // ""' <<<"$apps_values")"

        # Validate each Application's directory sources, honoring its exclusion glob.
        while IFS= read -r -d '' app_manifest; do
            [[ -f "$app_manifest" ]] || continue
            case "$app_manifest" in *.yaml|*.yml|*.json) ;; *) continue ;; esac
            [[ "$app_manifest" == "${cluster_dir}topf.yaml" ]] && continue
            [[ "$(yq e '.kind' "$app_manifest")" == "Application" ]] || continue
            while IFS= read -r dir_path; do
                [[ -n "$dir_path" && -d "$dir_path" ]] || continue
                exclude="$(yq e "(.spec.sources // [.spec.source])[] | select(.path == \"$dir_path\") | .directory.exclude // \"\"" "$app_manifest")"
                raw="$tmp/$cluster-$(echo "$dir_path" | tr '/' '-').yaml"
                : > "$raw"
                while IFS= read -r -d '' f; do
                    [[ -f "$f" ]] || continue
                    case "$f" in *.yaml|*.yml|*.json) ;; *) continue ;; esac
                    rel="${f#"$dir_path"/}"
                    # shellcheck disable=SC2053 # deliberately unquoted: $exclude is a glob, not a literal
                    [[ -n "$exclude" && "$rel" == $exclude ]] && continue
                    cat "$f" >> "$raw"
                    echo -e "\n---" >> "$raw"
                done < <(git ls-files --cached --others --exclude-standard -z -- "$dir_path" | sort -z)
                [[ -s "$raw" ]] && { conform "$dir_path ($cluster)" "$raw" || fail=1; }
            done < <(yq e -N '(.spec.sources // [.spec.source])[] | select(has("directory")) | .path' "$app_manifest")
        done < <(git ls-files --cached --others --exclude-standard -z -- "$cluster_dir" | sort -z)

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
            if [[ -n "$short_name" && "$short_name" != "$cluster" ]] && grep -Fq ".$REDACTED" "$rendered"; then
                error "apps/$app: DNS names must use '$short_name', not '$cluster', on $cluster"
                fail=1
            fi
            conform "$app ($cluster)" "$rendered" || fail=1
        done < <(yq e -N 'select(.kind == "Application") | .metadata.labels."REDACTED/name"' "$catalog")

        endgroup
    done

    if [[ "$fail" -ne 0 ]]; then
        echo "test_manifests.sh: FAILED" >&2
        exit 1
    fi
    echo "test_manifests.sh: OK"
)

check_manifest_selection() (
    scratch=$(mktemp -d)
    trap 'rm -rf "$scratch"' EXIT
    trap 'cat "$scratch/validation.log" >&2' ERR
    mkdir -p "$scratch"/{apps/templates,clusters/fixture/nested/deeper,clusters/fixture/output,bin}
    git init -q "$scratch"
    cd "$scratch"
    printf '%s\n' 'secrets.yaml' 'output/' > clusters/fixture/.gitignore
    printf '%s\n' 'kubernetesVersion: 1.37.1' 'excluded-topf-marker: true' > clusters/fixture/topf.yaml
    printf '%s\n' 'private-ignored-marker: true' > clusters/fixture/secrets.yaml
    printf '%s\n' 'private-output-marker: true' > clusters/fixture/output/node.yaml
    cat > clusters/fixture/apps.yaml <<'YAML'
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: apps-fixture
spec:
  sources:
    - path: clusters/fixture
      directory:
        recurse: true
        exclude: topf.yaml
    - path: apps
      helm:
        values: '{}'
YAML
    cat > clusters/fixture/nested/deeper/config.yaml <<'YAML'
apiVersion: v1
kind: ConfigMap
metadata:
  name: nested-yaml-fixture
YAML
    printf '%s\n' '{"apiVersion":"v1","kind":"ConfigMap","metadata":{"name":"nested-json-fixture"}}' > clusters/fixture/nested/deeper/config.json
    printf '%s\n' 'apiVersion: v2' 'name: apps' 'version: 0.1.0' > apps/Chart.yaml
    printf '%s\n' 'apiVersion: v1' 'kind: ConfigMap' 'metadata:' '  name: catalog-fixture' > apps/templates/catalog.yaml
    cat > bin/kubeconform <<'MOCK'
#!/usr/bin/env bash
set -euo pipefail
while [[ $# -gt 0 ]]; do
    if [[ "$1" == -kubernetes-version ]]; then
        [[ "$2" == "$EXPECTED_KUBERNETES_VERSION" ]]
        shift
    fi
    shift
done
cat >> "$MANIFEST_CAPTURE"
printf '\n---\n' >> "$MANIFEST_CAPTURE"
printf '%s\n' '{"resources":[]}'
MOCK
    chmod +x bin/kubeconform
    export PATH="$scratch/bin:$PATH"
    export MANIFEST_CAPTURE="$scratch/captured-manifests"
    export EXPECTED_KUBERNETES_VERSION=1.37.1
    unset KUBERNETES_VERSION

    for staged in false true; do
        if [[ "$staged" == true ]]; then
            git add clusters apps
        fi
        validate_manifests > "$scratch/validation.log" 2>&1
        for marker in apps-fixture nested-yaml-fixture nested-json-fixture; do
            grep -q "$marker" "$MANIFEST_CAPTURE" || { echo "Missing $marker" >&2; exit 1; }
        done
        if grep -Eq 'excluded-topf-marker|private-ignored-marker|private-output-marker' "$MANIFEST_CAPTURE"; then
            echo 'TOPF or private files reached manifest validation' >&2
            exit 1
        fi
        rm "$MANIFEST_CAPTURE"
    done
    echo 'PASS: Nested YAML and JSON manifests are included'
    echo 'PASS: topf.yaml and ignored files are excluded'
    echo 'PASS: Schema validation uses the cluster Kubernetes version'
    KUBERNETES_VERSION=1.36.1 EXPECTED_KUBERNETES_VERSION=1.36.1 \
        validate_manifests > "$scratch/validation.log" 2>&1
    echo 'PASS: An explicit Kubernetes version overrides the cluster version'
)

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    check_manifest_selection
    validate_manifests
fi
