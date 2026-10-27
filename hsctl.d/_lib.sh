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

# Runs `infisical <args...>` (stdin closed, so a missing session/project fails fast instead
# of blocking on an interactive prompt rendering over the stdout being captured here),
# retrying once against whichever of `infisical init` (no project linked — nothing in this
# repo creates a `.infisical.json`, so this is normal on a machine that's never linked one)
# or `infisical login` (invalid/expired session) its own stderr says is actually needed.
# Dispatches by matching the literal text infisical itself prints — "run infisical init"
# only ever appears in the no-project-linked message — rather than assuming every failure is
# a login problem: confirmed live, retrying via login alone can never fix a missing project
# link, and used to loop uselessly through a full browser re-auth for it before giving the
# same unhelpful error right back.
# Usage: out=$(hsctl_infisical_call secrets get X --env=prod --path=/y --plain) || <caller's own error>
hsctl_infisical_call() {
    local out err
    err=$(mktemp)
    if out=$(infisical "$@" </dev/null 2>"$err"); then
        rm -f "$err"
        printf '%s' "$out"
        return 0
    fi
    if grep -q "run infisical init" "$err"; then
        rm -f "$err"
        echo "hsctl: no Infisical project linked — starting 'infisical init' in \$HOME (select the HomeScale project)" >&2
        # Always $HOME, not wherever the caller's cwd happens to be — infisical discovers
        # .infisical.json by walking up from cwd on every call, so linking it here is what
        # makes it found regardless of where hsctl gets run from next, not just this one
        # invocation's own directory.
        (cd "$HOME" && infisical init --silent --domain https://app.infisical.com) || return 1
    else
        rm -f "$err"
        hsctl_infisical_login || return 1
    fi
    infisical "$@" </dev/null
}

# Resolve OIDC issuer/client ID from Infisical into HSCTL_OIDC_ISSUER_URL/HSCTL_OIDC_CLIENT_ID
# (memoized — a no-op if both are already set). Used by `hsctl get kubeconfig` to build
# the exec credential plugin config.
_hsctl_resolve_oidc() {
    [[ -n "${HSCTL_OIDC_ISSUER_URL:-}" && -n "${HSCTL_OIDC_CLIENT_ID:-}" ]] && return 0
    local secrets_json
    secrets_json=$(hsctl_infisical_call export --silent --env=prod --path=/k8s/oidc --format=json) || {
        hsctl_log_error "could not fetch OIDC config from Infisical (/k8s/oidc)"
        return 1
    }
    HSCTL_OIDC_ISSUER_URL=$(yq e -p json '.[] | select(.key == "OIDC_ISSUER_URL") | .value' <<< "$secrets_json" 2>/dev/null) || true
    HSCTL_OIDC_CLIENT_ID=$(yq e -p json '.[] | select(.key == "OIDC_CLIENT_ID") | .value' <<< "$secrets_json" 2>/dev/null) || true
    if [[ -z "$HSCTL_OIDC_ISSUER_URL" || -z "$HSCTL_OIDC_CLIENT_ID" ]]; then
        hsctl_log_error "OIDC config at /k8s/oidc is missing OIDC_ISSUER_URL or OIDC_CLIENT_ID"
        return 1
    fi
}

# Fetch a machine's BMC (Redfish) connection info from Infisical, at /bmc/<machine-id>.
# Usage: creds=$(hsctl_bmc_creds <machine-id>) || exit 1
#        IFS=$'\t' read -r bmc_ip bmc_user bmc_pass <<< "$creds"
hsctl_bmc_creds() {
    local id="$1" secrets_json
    secrets_json=$(hsctl_infisical_call export --silent --env=prod --path="/bmc/$id" --format=json) || {
        hsctl_log_error "failed to fetch BMC credentials for machine '$id' from Infisical (path /bmc/$id)"
        return 1
    }

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
