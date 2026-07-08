#!/usr/bin/env bash
# hsctl shared utilities — auto-sourced by hsctl before every command module
#
# Convention for read-only modules (e.g. get.sh):
#   1. module_main() pre-parses -o <format> and exports HSCTL_OUTPUT (default: table)
#   2. Call: hsctl_validate_output "$HSCTL_OUTPUT" || exit 1
#   3. Subcommand handlers read $HSCTL_OUTPUT and call hsctl_omni_output for yaml/json pass-through
#   4. Table rendering is resource-specific; yaml/json rendering is generic via hsctl_omni_output
#
# Convention for modules that take action against infrastructure (e.g. machine.sh):
#   report progress/outcome via hsctl_log_info/hsctl_log_action/hsctl_log_success/hsctl_log_error
#   rather than plain echo, so status output is consistent and timestamped.

# Validate -o output format; writes error and returns 1 on failure
hsctl_validate_output() {
    case "$1" in
        table|yaml|json) return 0 ;;
        *) echo "hsctl: unknown output format '$1' (valid: table, yaml, json)" >&2; return 1 ;;
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
# Used to identify clusterproxy-<name>-... NetBird peers without guessing at
# Kubernetes' variable-length pod-template-hash suffix.
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

# Fetch a machine's BMC (Redfish) connection info from Infisical, at /bmc/<machine-id>.
# Usage: creds=$(hsctl_bmc_creds <machine-id>) || exit 1
#        IFS=$'\t' read -r bmc_ip bmc_user bmc_pass <<< "$creds"
hsctl_bmc_creds() {
    local id="$1" secrets_json
    # stdin is /dev/null so a missing session can't drop into infisical's interactive login
    # wizard — that TUI renders over stdout, which we're capturing here, so it would otherwise
    # sit blocked on keystrokes the terminal never shows. Without a session it now fails fast
    # instead. stderr is left alone so infisical's own error output still reaches the terminal.
    # Uses if/else (rather than `cmd || true`) so a failed fetch is caught by its exit code here,
    # instead of tripping `set -e` or silently falling through with empty/garbage stdout.
    if ! secrets_json=$(infisical export --silent --env=prod --path="/bmc/$id" --format=json </dev/null); then
        hsctl_log_error "failed to fetch BMC credentials for machine '$id' from Infisical (path /bmc/$id) — try 'infisical login' first"
        return 1
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
