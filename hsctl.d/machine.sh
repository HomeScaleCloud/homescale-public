#!/usr/bin/env bash
# hsctl machine — take action directly against physical machines (IPMI/BMC/Talos)
#
# Unlike get.sh (read-only), these commands change real hardware state, so
# progress/outcome is reported via the hsctl_log_* helpers in _lib.sh rather
# than plain echo.
#
# BMC connection info is stored per-machine in Infisical at /bmc/<machine-id>
# (keys: IP, VENDOR_USERNAME, VENDOR_PASSWORD) — see hsctl_bmc_creds in _lib.sh.
#
# Redfish was tried first, but this fleet's Supermicro BMCs gate every Redfish
# endpoint behind a paid "SUM DCMS OOB" license, regardless of auth method.
# IPMI-over-LAN works unlicensed with the same credentials, so power control
# goes through ipmitool instead — except for a graceful "power off", which
# prefers talosctl (cordons/drains before shutdown). --force skips talosctl
# and hard-cuts power via IPMI instead, same as the other actions.

machine_usage() {
    echo "Usage: hsctl machine <action> [args...]"
    echo ""
    echo "Actions:"
    echo "  power on|reset <id|node-name>          Power on/reset a machine via its BMC (IPMI)"
    echo "  power off [--force] <id|node-name>      Gracefully shut down a machine via talosctl;"
    echo "                                           --force hard-cuts power via IPMI instead"
    exit 1
}

# Issue an IPMI chassis power command against a machine's BMC
# Usage: _machine_ipmi_power <machine-id> <bmc-ip> <user> <pass> <on|off|reset>
_machine_ipmi_power() {
    local id="$1" ip="$2" user="$3" pass="$4" verb="$5"
    local out

    hsctl_log_action "sending IPMI chassis power $verb to machine $id ($ip)"
    if out=$(ipmitool -I lanplus -H "$ip" -U "$user" -P "$pass" chassis power "$verb" 2>&1); then
        hsctl_log_success "machine $id: $out"
    else
        hsctl_log_error "machine $id: ipmitool chassis power $verb failed: $out"
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

    local input="" force=false
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --force) force=true; shift ;;
            *) input="$1"; shift ;;
        esac
    done
    [[ -z "$input" ]] && { echo "Usage: hsctl machine power <on|off|reset> [--force] <id|node-name>" >&2; exit 1; }

    local id
    id=$(hsctl_resolve_machine_id "$input") || { hsctl_log_error "no machine found for '$input'"; exit 1; }

    if [[ "$action" == "off" && "$force" == false ]]; then
        command -v talosctl &>/dev/null || { echo "hsctl machine power: talosctl is required for a graceful power off (brew install talosctl), or pass --force to hard-cut power via IPMI" >&2; exit 1; }
        _machine_talos_shutdown "$id" || exit 1
        return 0
    fi

    command -v ipmitool &>/dev/null || { echo "hsctl machine power: ipmitool is required (brew install ipmitool)" >&2; exit 1; }

    local creds ip user pass
    creds=$(hsctl_bmc_creds "$id") || exit 1
    IFS=$'\t' read -r ip user pass <<< "$creds"

    _machine_ipmi_power "$id" "$ip" "$user" "$pass" "$action"
}

machine_main() {
    [[ $# -eq 0 ]] && machine_usage

    local action; action="$(tr '[:upper:]' '[:lower:]' <<< "$1")"; shift
    case "$action" in
        power|pow)
            machine_power "$@"
            ;;
        *) echo "hsctl machine: unknown action '$action'" >&2; machine_usage ;;
    esac
}
