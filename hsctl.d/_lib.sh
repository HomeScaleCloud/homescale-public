#!/usr/bin/env bash
# hsctl shared utilities — auto-sourced by hsctl before every command module
#
# Convention for modules:
#   1. module_main() pre-parses -o <format> and exports HSCTL_OUTPUT (default: table)
#   2. Call: hsctl_validate_output "$HSCTL_OUTPUT" || exit 1
#   3. Subcommand handlers read $HSCTL_OUTPUT and call hsctl_omni_output for yaml/json pass-through
#   4. Table rendering is resource-specific; yaml/json rendering is generic via hsctl_omni_output

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
