#!/usr/bin/env bash
# hsctl machine — take action directly against physical machines (IPMI/BMC/Talos)
#
# Unlike get.sh (read-only), progress/outcome here is reported via the hsctl_log_*
# helpers in _lib.sh rather than plain echo. BMC creds come from Infisical at
# /bmc/<machine-id> (see hsctl_bmc_creds in _lib.sh).
#
# Power control goes through ipmitool, not Redfish: this fleet's Supermicro BMCs
# gate Redfish behind a paid license, but IPMI-over-LAN works unlicensed with the
# same creds. Graceful "power off" prefers talosctl instead (cordons/drains first);
# --force hard-cuts power via IPMI like the other actions.
#
# ipmitool calls prefer RMCP+ (-I lanplus), falling back to legacy IPMI 1.5 (-I lan)
# when a BMC's RMCP+/RAKP stack is broken — see docs/operations/hsctl.md for details.

machine_usage() {
    echo "Usage: hsctl machine <action> [args...]"
    echo ""
    echo "Actions:"
    echo "  power on|reset <id|node-name>...          Power on/reset one or more machines via their BMC (IPMI)"
    echo "  power off [--force] <id|node-name>...     Gracefully shut down one or more machines via talosctl;"
    echo "                                              --force hard-cuts power via IPMI instead"
    echo "  bmcreset <id|node-name>                   Cold-restart the machine's BMC (host power untouched)"
    exit 1
}

# Run an ipmitool command, falling back from RMCP+ (lanplus) to legacy IPMI 1.5 (lan)
# if the lanplus session can't be established. Prints ipmitool's output either way.
# Usage: out=$(_machine_ipmi <bmc-ip> <user> <pass> <ipmitool args...>) || return 1
_machine_ipmi() {
    local ip="$1" user="$2" pass="$3"; shift 3
    local out
    if out=$(ipmitool -I lanplus -H "$ip" -U "$user" -P "$pass" "$@" 2>&1); then
        printf '%s' "$out"
        return 0
    fi
    if [[ "$out" == *"RMCP+"* || "$out" == *"RAKP"* || "$out" == *"invalid role"* ]]; then
        if out=$(ipmitool -I lan -H "$ip" -U "$user" -P "$pass" "$@" 2>&1); then
            printf '%s' "$out"
            return 0
        fi
    fi
    printf '%s' "$out"
    return 1
}

# Issue an IPMI chassis power command against a machine's BMC
# Usage: _machine_ipmi_power <machine-id> <bmc-ip> <user> <pass> <on|off|reset>
_machine_ipmi_power() {
    local id="$1" ip="$2" user="$3" pass="$4" verb="$5"
    local out

    hsctl_log_action "sending IPMI chassis power $verb to machine $id ($ip)"
    if out=$(_machine_ipmi "$ip" "$user" "$pass" chassis power "$verb"); then
        hsctl_log_success "machine $id: $out"
    else
        hsctl_log_error "machine $id: ipmitool chassis power $verb failed: $out"
        return 1
    fi
}

# Cold-restart a machine's BMC (host power unaffected, ~1-2 min to come back).
# Usage: _machine_bmc_reset <machine-id> <bmc-ip> <user> <pass>
_machine_bmc_reset() {
    local id="$1" ip="$2" user="$3" pass="$4"
    local out

    hsctl_log_action "sending IPMI 'mc reset cold' to machine $id BMC ($ip)"
    if out=$(_machine_ipmi "$ip" "$user" "$pass" mc reset cold); then
        hsctl_log_success "machine $id: BMC cold reset issued${out:+ ($out)} — allow 1-2 min for it to come back"
    else
        hsctl_log_error "machine $id: ipmitool mc reset cold failed: $out"
        exit 1
    fi
}

# Gracefully shut a machine down via talosctl, proxied through Omni by machine UUID.
# Usage: _machine_talos_shutdown <machine-id>
_machine_talos_shutdown() {
    local id="$1"

    hsctl_log_action "sending talos API shutdown to machine $id"
    local out
    if out=$(talosctl -n "$id" shutdown 2>&1); then
        hsctl_log_success "machine $id: $out"
        return 0
    else
        hsctl_log_error "machine $id: talosctl shutdown failed: $out"
        return 1
    fi
}

machine_power() {
    local action="${1:-}"
    [[ -z "$action" ]] && machine_usage
    shift

    case "$action" in
        on|off|reset) ;;
        *) echo "hsctl machine power: unknown action '$action'" >&2; machine_usage ;;
    esac

    local -a inputs=()
    local force=false
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --force) force=true; shift ;;
            *) inputs+=("$1"); shift ;;
        esac
    done
    [[ ${#inputs[@]} -eq 0 ]] && { echo "Usage: hsctl machine power <on|off|reset> [--force] <id|node-name> [<id|node-name>...]" >&2; exit 1; }

    if [[ "$action" == "off" && "$force" == false ]]; then
        command -v talosctl &>/dev/null || { echo "hsctl machine power: talosctl is required for a graceful power off (brew install talosctl), or pass --force to hard-cut power via IPMI" >&2; exit 1; }
    else
        command -v ipmitool &>/dev/null || { echo "hsctl machine power: ipmitool is required (brew install ipmitool)" >&2; exit 1; }
    fi

    local failed=false
    local input id
    for input in "${inputs[@]}"; do
        id=$(hsctl_resolve_machine_id "$input") || { hsctl_log_error "no machine found for '$input'"; failed=true; continue; }

        if [[ "$action" == "off" && "$force" == false ]]; then
            _machine_talos_shutdown "$id" || failed=true
            continue
        fi

        local creds ip user pass
        creds=$(hsctl_bmc_creds "$id") || { failed=true; continue; }
        IFS=$'\t' read -r ip user pass <<< "$creds"

        _machine_ipmi_power "$id" "$ip" "$user" "$pass" "$action" || failed=true
    done

    [[ "$failed" == true ]] && exit 1
    return 0
}

machine_bmcreset() {
    local input="${1:-}"
    [[ -z "$input" ]] && { echo "Usage: hsctl machine bmcreset <id|node-name>" >&2; exit 1; }

    command -v ipmitool &>/dev/null || { echo "hsctl machine bmcreset: ipmitool is required (brew install ipmitool)" >&2; exit 1; }

    local id
    id=$(hsctl_resolve_machine_id "$input") || { hsctl_log_error "no machine found for '$input'"; exit 1; }

    local creds ip user pass
    creds=$(hsctl_bmc_creds "$id") || exit 1
    IFS=$'\t' read -r ip user pass <<< "$creds"

    _machine_bmc_reset "$id" "$ip" "$user" "$pass"
}

machine_main() {
    [[ $# -eq 0 ]] && machine_usage

    local action; action="$(tr '[:upper:]' '[:lower:]' <<< "$1")"; shift
    case "$action" in
        power|pow)
            machine_power "$@"
            ;;
        bmcreset|bmc-reset)
            machine_bmcreset "$@"
            ;;
        *) echo "hsctl machine: unknown action '$action'" >&2; machine_usage ;;
    esac
}
