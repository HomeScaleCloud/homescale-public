#!/usr/bin/env bash
# hsctl shared utilities — auto-sourced by hsctl before every command module
#
# Read-only modules (e.g. get.sh): module_main() pre-parses -o <format>, exports
# HSCTL_OUTPUT (default: table), calls hsctl_validate_output, and handlers use
# hsctl_omni_output for yaml/json pass-through.
#
# Action modules (e.g. machine.sh): report via hsctl_log_info/action/success/error
# rather than plain echo, for consistent timestamped status output.

# Validate -o output format; writes error and returns 1 on failure
hsctl_validate_output() {
    case "$1" in
        table|yaml|json|ansible) return 0 ;;
        *) echo "hsctl: unknown output format '$1' (valid: table, yaml, json, ansible)" >&2; return 1 ;;
    esac
}

# Render an omnictl resource or resource list as yaml or json
# Usage: hsctl_omni_output yaml|json <resource-type> [extra omnictl args...]
hsctl_omni_output() {
    local fmt="$1" rtype="$2"; shift 2
    case "$fmt" in
        yaml) omnictl get "$rtype" "$@" -o yaml ;;
        json) omnictl get "$rtype" "$@" -o yaml | yq -o json ;;
    esac
}

# Cluster names known to this repo checkout (clusters/<name>/), comma-joined.
hsctl_cluster_names() {
    find "$HSCTL_REPO_ROOT/clusters" -mindepth 1 -maxdepth 1 -type d -exec basename {} \; 2>/dev/null | paste -sd, -
}

# Resolve a machine's Omni UUID or Kubernetes node name to its UUID.
# Usage: id=$(hsctl_resolve_machine_id <id-or-node-name>) || echo "not found"
hsctl_resolve_machine_id() {
    local input="$1"
    if [[ "$input" =~ ^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$ ]]; then
        printf '%s\n' "$input"
        return 0
    fi
    local id
    id=$(omnictl get clustermachineidentity -o yaml | \
        yq e 'select(.spec.nodename == "'"$input"'") | .metadata.id' 2>/dev/null | head -1)
    [[ -z "$id" ]] && return 1
    printf '%s\n' "$id"
}

# Interactively runs `infisical login` to retry a secret fetch after an invalid session.
# Usage: hsctl_infisical_login || return 1
hsctl_infisical_login() {
    echo "hsctl: no valid Infisical session — starting 'infisical login'" >&2
    infisical login --silent --domain https://app.infisical.com
}

# Resolve OIDC issuer/client ID from Infisical into HSCTL_OIDC_ISSUER_URL/HSCTL_OIDC_CLIENT_ID
# (memoized — a no-op if both are already set). Shared by `hsctl get kubeconfig` (to build
# the exec credential plugin config) and hsctl_oidc_username (to mint a token to decode).
_hsctl_resolve_oidc() {
    [[ -n "${HSCTL_OIDC_ISSUER_URL:-}" && -n "${HSCTL_OIDC_CLIENT_ID:-}" ]] && return 0
    local secrets_json
    if ! secrets_json=$(infisical export --silent --env=prod --path=/k8s/oidc --format=json </dev/null); then
        hsctl_infisical_login || { hsctl_log_error "infisical login failed"; return 1; }
        if ! secrets_json=$(infisical export --silent --env=prod --path=/k8s/oidc --format=json </dev/null); then
            hsctl_log_error "could not fetch OIDC config from Infisical (/k8s/oidc)"
            return 1
        fi
    fi
    HSCTL_OIDC_ISSUER_URL=$(yq e -p json '.[] | select(.key == "OIDC_ISSUER_URL") | .value' <<< "$secrets_json" 2>/dev/null) || true
    HSCTL_OIDC_CLIENT_ID=$(yq e -p json '.[] | select(.key == "OIDC_CLIENT_ID") | .value' <<< "$secrets_json" 2>/dev/null) || true
    if [[ -z "$HSCTL_OIDC_ISSUER_URL" || -z "$HSCTL_OIDC_CLIENT_ID" ]]; then
        hsctl_log_error "OIDC config at /k8s/oidc is missing OIDC_ISSUER_URL or OIDC_CLIENT_ID"
        return 1
    fi
}

# HomeScale identity (the local-part of the Entra ID `email` claim, e.g. "max" for
# max@REDACTED) via the same kubelogin plugin `hsctl get kubeconfig core` already wires
# up as the `core` context's k8s exec credential. Deliberately reads the issuer URL/client ID
# straight out of the *local kubeconfig file* (`kubectl config view`, no Infisical/network
# call) rather than re-fetching them from Infisical: only a handful of people have Infisical
# access at all, but ~everyone running `hsctl run` already has a working `core` context (it's
# required for -e remote to work in the first place), and those two values aren't secret —
# they're plain OIDC discovery/client identifiers, already sitting in kubectl's own config
# once `core` has been set up once. Then calls kubelogin with those exact same args, which
# reuses its on-disk token cache (~/.kube/cache/oidc-login) — silent/non-interactive as long
# as a still-valid or refreshable token is already cached, which it will be immediately after
# _run_remote's own `kubectl ... --context core` calls warm it.
#
# Fails closed (silently, no Infisical login prompt, no browser flow of its own) if no `core`
# context/exec config is present locally yet — callers have no whoami-style fallback for this;
# see run.sh's _run_job_owner. Echoes nothing and returns 1 on any failure.
hsctl_oidc_username() {
    command -v kubectl &>/dev/null || return 1
    command -v jq &>/dev/null || return 1

    local exec_json issuer client_id scopes
    exec_json=$(kubectl config view -o json 2>/dev/null | jq -c '.users[] | select(.name == "core") | .user.exec // empty') || return 1
    [[ -z "$exec_json" ]] && return 1
    issuer=$(jq -r '.args[] | select(startswith("--oidc-issuer-url=")) | ltrimstr("--oidc-issuer-url=")' <<< "$exec_json" 2>/dev/null)
    client_id=$(jq -r '.args[] | select(startswith("--oidc-client-id=")) | ltrimstr("--oidc-client-id=")' <<< "$exec_json" 2>/dev/null)
    scopes=$(jq -r '.args[] | select(startswith("--oidc-extra-scope=")) | ltrimstr("--oidc-extra-scope=")' <<< "$exec_json" 2>/dev/null)
    [[ -z "$issuer" || -z "$client_id" ]] && return 1

    # Reuses the exact same args (including scopes) as the core context's own exec config so
    # this hits kubelogin's already-warm cache entry instead of a distinct one.
    local cred token payload pad email
    cred=$(kubectl oidc-login get-token \
        --oidc-issuer-url="$issuer" \
        --oidc-client-id="$client_id" \
        ${scopes:+--oidc-extra-scope="$scopes"} \
        2>/dev/null) || return 1
    token=$(jq -r '.status.token // empty' <<< "$cred" 2>/dev/null)
    [[ -z "$token" ]] && return 1

    # id_token is a JWT: header.payload.signature, base64url — decode the payload only.
    payload="${token#*.}"; payload="${payload%.*}"
    payload=$(tr '_-' '/+' <<< "$payload")
    pad=$(( (4 - ${#payload} % 4) % 4 ))
    for ((_i = 0; _i < pad; _i++)); do payload+="="; done

    email=$(base64 -d <<< "$payload" 2>/dev/null | jq -r '.email // .preferred_username // empty' 2>/dev/null)
    [[ -z "$email" ]] && return 1
    echo "${email%%@*}"
}

# Fetch a machine's BMC (Redfish) connection info from Infisical, at /bmc/<machine-id>.
# Usage: creds=$(hsctl_bmc_creds <machine-id>) || exit 1
#        IFS=$'\t' read -r bmc_ip bmc_user bmc_pass <<< "$creds"
hsctl_bmc_creds() {
    local id="$1" secrets_json
    # stdin is /dev/null so a missing session fails fast instead of blocking on infisical's
    # interactive login wizard (which would otherwise render over the stdout we're capturing).
    if ! secrets_json=$(infisical export --silent --env=prod --path="/bmc/$id" --format=json </dev/null); then
        hsctl_infisical_login || { hsctl_log_error "infisical login failed"; return 1; }
        if ! secrets_json=$(infisical export --silent --env=prod --path="/bmc/$id" --format=json </dev/null); then
            hsctl_log_error "failed to fetch BMC credentials for machine '$id' from Infisical (path /bmc/$id)"
            return 1
        fi
    fi

    # infisical export --format=json is an array of secret objects (.key/.value), not a flat map
    local ip user pass
    ip=$(yq e -p json '.[] | select(.key == "IP") | .value' <<< "$secrets_json" 2>/dev/null) || true
    user=$(yq e -p json '.[] | select(.key == "VENDOR_USERNAME") | .value' <<< "$secrets_json" 2>/dev/null) || true
    pass=$(yq e -p json '.[] | select(.key == "VENDOR_PASSWORD") | .value' <<< "$secrets_json" 2>/dev/null) || true
    if [[ -z "$ip" || -z "$user" || -z "$pass" ]]; then
        hsctl_log_error "BMC secret at /bmc/$id is missing IP, VENDOR_USERNAME, or VENDOR_PASSWORD"
        return 1
    fi
    printf '%s\t%s\t%s\n' "$ip" "$user" "$pass"
}

# Leveled, timestamped status logging — for commands that take action against
# infrastructure (as opposed to `get`, which only displays data).
# Usage: hsctl_log_info|hsctl_log_action|hsctl_log_success|hsctl_log_error <message...>
hsctl_log() {
    local level="$1"; shift
    printf '%s [%s] %s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$level" "$*" >&2
}
hsctl_log_info()    { hsctl_log INFO "$@"; }
hsctl_log_action()  { hsctl_log ACTION "$@"; }
hsctl_log_success() { hsctl_log OK "$@"; }
hsctl_log_error()   { hsctl_log ERROR "$@"; }
