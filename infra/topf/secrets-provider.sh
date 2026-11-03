#!/usr/bin/env bash
set -euo pipefail
umask 077

provider_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
export HSCTL_REPO_ROOT="${HSCTL_REPO_ROOT:-$provider_root}"

fail() { printf 'TOPF secrets: %s\n' "$*" >&2; exit 1; }

[[ $# -eq 3 && "$1" == secrets ]] || fail "expected: secrets get|put <cluster>"
case "$3" in
    production) shortname=prod ;;
    development) shortname=dev ;;
    *) fail "unknown cluster: $3" ;;
esac

project="$HSCTL_REPO_ROOT/clusters/$3"
cache="$project/secrets.yaml"
pending="$project/secrets.pending.yaml"
secret_path="/k8s/talos/$shortname"
command -v jq >/dev/null || fail "jq is required"

private_files() {
    local file
    for file in "$cache" "$pending"; do
        [[ ! -L "$file" && ( ! -e "$file" || -f "$file" ) ]] || fail "refusing non-regular secret file: $file"
        [[ ! -f "$file" ]] || chmod 600 "$file"
    done
}

stage_pending() (
    temporary=$(mktemp "$project/.secrets.XXXXXX")
    trap 'rm -f "$temporary"' EXIT
    cat > "$temporary"
    [[ -s "$temporary" ]] || fail "refusing to store an empty bundle"
    ln "$temporary" "$pending" || fail "pending bundle already exists; finish its backup before creating another"
)

store_cache() {
    local temporary
    temporary=$(mktemp "$project/.secrets.XXXXXX")
    chmod 600 "$temporary"
    if ! cat > "$temporary"; then
        rm -f "$temporary"
        return 1
    fi
    mv "$temporary" "$cache"
}

push_pending() {
    infisical secrets set "SECRETS_YAML=@$pending" --silent --path="$secret_path" --env=prod --type=shared </dev/null >/dev/null ||
        fail "bundle retained at $pending; retry with --init-secrets to finish its backup"
    chmod 600 "$pending"
    mv "$pending" "$cache"
}

case "$2" in
    get)
        if [[ -n "${HSCTL_TOPF_SECRETS_FILE:-}" ]]; then
            [[ -s "$HSCTL_TOPF_SECRETS_FILE" ]] || fail "the supplied secrets bundle is missing or empty"
            cat "$HSCTL_TOPF_SECRETS_FILE"
            exit 0
        fi
        private_files
        if [[ "${HSCTL_TOPF_INIT_SECRETS:-false}" != true && -f "$pending" ]]; then
            fail "an unbacked-up bundle exists; retry initialization with --init-secrets"
        fi
        if [[ -s "$cache" && "${HSCTL_TOPF_REFRESH_SECRETS:-false}" != true && "${HSCTL_TOPF_INIT_SECRETS:-false}" != true ]]; then
            cat "$cache"
            exit 0
        fi
        raw=$(infisical export --silent --env=prod --path="$secret_path" --format=json </dev/null) || exit 1
        bundle=$(jq -r '[.[] | select(.key == "SECRETS_YAML") | .value][0] // ""' <<<"$raw")
        if [[ -n "$bundle" ]]; then
            for file in "$cache" "$pending"; do
                [[ ! -s "$file" || "$bundle" == "$(cat "$file")" ]] || fail "remote bundle differs from $file; verify the correct CA before replacing it"
            done
            printf '%s' "$bundle" | store_cache
            rm -f "$pending"
        elif [[ "${HSCTL_TOPF_INIT_SECRETS:-false}" == true ]]; then
            if [[ -s "$pending" ]]; then
                [[ ! -s "$cache" || "$(cat "$cache")" == "$(cat "$pending")" ]] || fail "local bundles disagree; verify the correct CA before recovery"
                push_pending
            elif [[ -s "$cache" ]]; then
                stage_pending < "$cache"
                push_pending
            elif jq -e 'any(.[]; (.key == "TALOSCONFIG" or .key == "KUBECONFIG") and (.value | length > 0))' <<<"$raw" >/dev/null; then
                fail "restore SECRETS_YAML from the existing cluster; refusing to generate a replacement CA"
            else
                exit 0
            fi
        else
            fail "SECRETS_YAML is absent; restore it or initialize a new cluster explicitly with --init-secrets"
        fi
        cat "$cache"
        ;;
    put)
        [[ "${HSCTL_TOPF_INIT_SECRETS:-false}" == true && -z "${HSCTL_TOPF_SECRETS_FILE:-}" ]] || fail "creating a bundle requires --init-secrets"
        private_files
        [[ ! -s "$cache" ]] || fail "refusing to replace an existing cluster bundle"
        stage_pending
        if [[ -s "$cache" ]]; then
            rm -f "$pending"
            fail "another initialization completed; refusing to replace its bundle"
        fi
        push_pending
        ;;
    *)
        fail "unknown provider operation: $2"
        ;;
esac
