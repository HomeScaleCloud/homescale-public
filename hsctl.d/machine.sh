#!/usr/bin/env bash
# hsctl machine — take action directly against physical machines (IPMI/BMC)
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
# goes through ipmitool instead.

machine_usage() {
    echo "Usage: hsctl machine <action> [args...]"
    echo ""
    echo "Actions:"
    echo "  power on|off|reset <id|node-name>   Power on/off/reset a machine via its BMC (IPMI)"
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

machine_power() {
    command -v ipmitool &>/dev/null || { echo "hsctl machine power: ipmitool is required (brew install ipmitool)" >&2; exit 1; }

    local action="${1:-}"
    [[ -z "$action" ]] && machine_usage
    shift

    local input="${1:-}"
    [[ -z "$input" ]] && { echo "Usage: hsctl machine power <on|off|reset> <id|node-name>" >&2; exit 1; }

    case "$action" in
        on|off|reset) ;;
        *) echo "hsctl machine power: unknown action '$action'" >&2; machine_usage ;;
    esac

    local id
    id=$(hsctl_resolve_machine_id "$input") || { hsctl_log_error "no machine found for '$input'"; exit 1; }

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
