#!/usr/bin/env bash
# hsctl get — query Omni/cluster resources
#
# Output format: controlled by -o flag (table, yaml, json); default is table
# HSCTL_OUTPUT is set by get_main and read by all subcommand handlers

get_usage() {
    echo "Usage: hsctl get <resource> [-o table|yaml|json] [flags...]"
    echo ""
    echo "Resources:"
    echo "  machines [--cluster <name>]   List all machines; enriches with node name for assigned ones"
    echo "  machine  <id>                 Show details for a specific machine"
    exit 1
}

# Reads ClusterMachineIdentity YAML from stdin, prints table rows (no header)
_machine_table_rows() {
    yq e '[
      .metadata.id,
      (.spec.nodename // "-"),
      (.metadata.labels["omni.sidero.dev/cluster"] // "-"),
      (.metadata.labels | to_entries | map(select(.key | test("omni.sidero.dev/role-"))) | .[0].key | sub("omni.sidero.dev/role-"; "") // "-"),
      (.spec.nodeips // [] | join(","))
    ] | @tsv' | \
    while IFS=$'\t' read -r id nodename cluster role ips; do
        printf "%-38s  %-16s  %-20s  %-14s  %s\n" "$id" "$nodename" "$cluster" "$role" "$ips"
    done
}

get_machines() {
    local cluster_filter=""
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --cluster|-c) cluster_filter="$2"; shift 2 ;;
            *) echo "hsctl get machines: unknown flag '$1'" >&2; get_usage ;;
        esac
    done

    # status_tsv: id, IPv4 addresses — from MachineStatus, exists for all connected machines
    # Note: no 2>&1 here so omnictl's stderr reaches the terminal (auth flow, errors)
    local status_tsv identity_tsv
    status_tsv=$(omnictl get machinestatus -o yaml | \
        yq e '[
          .metadata.id,
          (.spec.network.addresses // [] | map(select(test("^[0-9]"))) | map(sub("/[0-9]+$"; "")) | join(","))
        ] | @tsv' 2>/dev/null || true)
    # identity_tsv: id, nodename, cluster, role — assigned machines only
    identity_tsv=$(omnictl get clustermachineidentity -o yaml | \
        yq e '[
          .metadata.id,
          (.spec.nodename // "-"),
          (.metadata.labels["omni.sidero.dev/cluster"] // "-"),
          (.metadata.labels | to_entries | map(select(.key | test("omni.sidero.dev/role-"))) | .[0].key | sub("omni.sidero.dev/role-"; "") // "-")
        ] | @tsv' 2>/dev/null || true)

    case "$HSCTL_OUTPUT" in
        table)
            printf "%-38s  %-16s  %-20s  %-14s  %s\n" "MACHINE ID" "NODE NAME" "CLUSTER" "ROLE" "NODE IPs"
            while IFS=$'\t' read -r machine_id ips; do
                identity_row=""
                [[ -n "$identity_tsv" ]] && identity_row=$(awk -F'\t' -v id="$machine_id" '$1==id{print;exit}' <<< "$identity_tsv")
                if [[ -n "$identity_row" ]]; then
                    IFS=$'\t' read -r _ nodename cluster role <<< "$identity_row"
                    [[ -n "$cluster_filter" && "$cluster" != "$cluster_filter" ]] && continue
                    printf "%-38s  %-16s  %-20s  %-14s  %s\n" "$machine_id" "$nodename" "$cluster" "$role" "$ips"
                else
                    [[ -n "$cluster_filter" ]] && continue
                    printf "%-38s  %-16s  %-20s  %-14s  %s\n" "$machine_id" "-" "-" "-" "$ips"
                fi
            done <<< "$status_tsv"
            ;;
        yaml) omnictl get machinestatus -o yaml ;;
        json) omnictl get machinestatus -o yaml | yq -o json ;;
    esac
}

get_machine() {
    local input="${1:-}"
    [[ -z "$input" ]] && { echo "Usage: hsctl get machine <id|node-name>"; exit 1; }

    # Resolve node name → UUID via ClusterMachineIdentity if input isn't already a UUID
    local id
    if [[ "$input" =~ ^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$ ]]; then
        id="$input"
    else
        id=$(omnictl get clustermachineidentity -o yaml | \
            yq e 'select(.spec.nodename == "'"$input"'") | .metadata.id' 2>/dev/null | head -1)
        if [[ -z "$id" ]]; then
            echo "hsctl: no machine found with node name '$input'" >&2
            exit 1
        fi
    fi

    case "$HSCTL_OUTPUT" in
        table)
            printf "%-38s  %-16s  %-20s  %-14s  %s\n" "MACHINE ID" "NODE NAME" "CLUSTER" "ROLE" "NODE IPs"
            local identity_yaml
            identity_yaml=$(omnictl get clustermachineidentity "$id" -o yaml)
            if printf '%s\n' "$identity_yaml" | grep -q "^metadata:"; then
                printf '%s\n' "$identity_yaml" | _machine_table_rows
            else
                local mgmt_addr
                mgmt_addr=$(omnictl get machine "$id" -o yaml | yq e '.spec.managementaddress // "-"')
                printf "%-38s  %-16s  %-20s  %-14s  %s\n" "$id" "-" "-" "-" "$mgmt_addr"
            fi
            ;;
        yaml|json) hsctl_omni_output "$HSCTL_OUTPUT" machine "$id" ;;
    esac
}

get_main() {
    HSCTL_OUTPUT="table"
    local args=()
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -o|--output) HSCTL_OUTPUT="$2"; shift 2 ;;
            *) args+=("$1"); shift ;;
        esac
    done
    hsctl_validate_output "$HSCTL_OUTPUT" || exit 1
    set -- "${args[@]+"${args[@]}"}"

    [[ $# -eq 0 ]] && get_usage

    local resource; resource="$(tr '[:upper:]' '[:lower:]' <<< "$1")"; shift
    case "$resource" in
        machine|machines|m)
            if [[ $# -gt 0 && "$1" != -* ]]; then
                get_machine "$@"
            else
                get_machines "$@"
            fi
            ;;
        *) echo "hsctl get: unknown resource '$resource'" >&2; get_usage ;;
    esac
}
