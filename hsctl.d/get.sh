#!/usr/bin/env bash
# hsctl get — query Omni/cluster resources
#
# Output format: controlled by -o flag (table, yaml, json); default is table
# HSCTL_OUTPUT is set by get_main and read by all subcommand handlers

get_usage() {
    echo "Usage: hsctl get <resource> [-o table|yaml|json] [flags...]"
    echo ""
    echo "Resources:"
    echo "  clusters                      List Kubernetes clusters reachable via NetBird"
    echo "  kubeconfig <cluster>          Write kubeconfig context for a cluster"
    echo "  machines [--cluster <name>]   List all machines; enriches with node name for assigned ones"
    echo "  machine  <id>                 Show details for a specific machine"
    echo "  snapshot <app>                List restic snapshots for an app"
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

get_snapshot() {
    local app="${1:-}"
    [[ -z "$app" ]] && { echo "Usage: hsctl get snapshot <app>"; exit 1; }

    local app_yaml="$HSCTL_REPO_ROOT/apps/$app/app.yaml"
    if [[ ! -f "$app_yaml" ]]; then
        echo "hsctl: app '$app' not found (expected $app_yaml; override with HSCTL_REPO_ROOT)" >&2
        exit 1
    fi

    local namespace secret pod_name tmpfile
    namespace=$(yq '.namespace' "$app_yaml")
    secret="${app}-volsync-repo"
    pod_name="hsctl-restic-${app}"

    # Delete any leftover pod from a previous run
    kubectl -n "$namespace" delete pod "$pod_name" --ignore-not-found=true 2>/dev/null

    local tmpfile
    tmpfile=$(mktemp /tmp/hsctl-XXXXXX)

    printf 'apiVersion: v1
kind: Pod
metadata:
  name: %s
  namespace: %s
spec:
  restartPolicy: Never
  containers:
  - name: restic
    image: restic/restic
    args: ["snapshots"]
    envFrom:
    - secretRef:
        name: %s
' "$pod_name" "$namespace" "$secret" > "$tmpfile"

    kubectl apply -f "$tmpfile" >/dev/null
    rm -f "$tmpfile"

    while true; do
        phase=$(kubectl -n "$namespace" get pod "$pod_name" -o jsonpath='{.status.phase}' 2>/dev/null || echo "Pending")
        case "$phase" in
            Succeeded) break ;;
            Failed)
                echo "Pod failed — logs:" >&2
                kubectl -n "$namespace" logs "$pod_name" >&2
                kubectl -n "$namespace" delete pod "$pod_name" --ignore-not-found=true >/dev/null 2>&1
                exit 1 ;;
            *) sleep 2 ;;
        esac
    done

    kubectl -n "$namespace" logs "$pod_name"
    kubectl -n "$namespace" delete pod "$pod_name" --ignore-not-found=true >/dev/null 2>&1
}

get_clusters() {
    local netbird_json talos_tsv cluster_names
    netbird_json=$(netbird status --json 2>/dev/null || echo '{}')
    talos_tsv=$(omnictl get clusters -o yaml 2>/dev/null | \
        yq e '[.metadata.id, (.spec.talosversion // "?")] | @tsv' - 2>/dev/null || true)
    cluster_names=$(hsctl_cluster_names)

    python3 - "$HSCTL_OUTPUT" "$talos_tsv" "$netbird_json" "$cluster_names" <<'PYEOF'
import json, sys, urllib.request, ssl

output_fmt    = sys.argv[1]
talos_tsv     = sys.argv[2]
netbird_json  = sys.argv[3]
cluster_names = [c for c in sys.argv[4].split(',') if c]

talos_versions = {}
for line in talos_tsv.strip().splitlines():
    parts = line.split('\t')
    if len(parts) == 2:
        talos_versions[parts[0]] = parts[1]

def match_cluster(fqdn):
    # clusterproxy-<cluster>-<pod-template-hash>-<pod-suffix>-... — the hash
    # is a variable-length k8s-generated suffix, so match against known
    # cluster names (longest first, in case one name prefixes another)
    # rather than guessing at the hash format/length.
    best = None
    for c in cluster_names:
        if fqdn.startswith(f'clusterproxy-{c}-') and (best is None or len(c) > len(best)):
            best = c
    return best

data = json.loads(netbird_json)
seen = {}
clusters = []
for p in data.get('peers', {}).get('details', []):
    c = match_cluster(p.get('fqdn', ''))
    if c and c not in seen:
        seen[c] = True
        fqdn = f'k8s.{c}REDACTED'
        ctx = ssl.create_default_context()
        ctx.check_hostname = False
        ctx.verify_mode = ssl.CERT_NONE
        try:
            k8s_ver = json.loads(urllib.request.urlopen(f'https://{fqdn}/version', timeout=5, context=ctx).read()).get('gitVersion', '?')
        except Exception:
            k8s_ver = '?'
        clusters.append({'name': c, 'fqdn': fqdn, 'k8s_version': k8s_ver, 'talos_version': talos_versions.get(c, '?')})

if output_fmt == 'json':
    print(json.dumps(clusters, indent=2))
elif output_fmt == 'yaml':
    for cl in clusters:
        print(f'- name: {cl["name"]}')
        print(f'  fqdn: {cl["fqdn"]}')
        print(f'  k8sVersion: {cl["k8s_version"]}')
        print(f'  talosVersion: {cl["talos_version"]}')
else:
    print(f'{"CLUSTER":<20}  {"API FQDN":<44}  {"K8S VERSION":<14}  TALOS VERSION')
    for cl in clusters:
        print(f'{cl["name"]:<20}  {cl["fqdn"]:<44}  {cl["k8s_version"]:<14}  {cl["talos_version"]}')
PYEOF
}

get_kubeconfig() {
    local cluster="${1:-}"
    [[ -z "$cluster" ]] && { echo "Usage: hsctl get kubeconfig <cluster>"; exit 1; }

    local kubeconfig="${KUBECONFIG:-$HOME/.kube/config}"
    local fqdn="k8s.${cluster}REDACTED"

    python3 - "$cluster" "$fqdn" "$kubeconfig" <<'PYEOF'
import json, sys, ssl, urllib.request
from pathlib import Path

cluster, fqdn, kubeconfig_path = sys.argv[1], sys.argv[2], sys.argv[3]

ctx = ssl.create_default_context()
ctx.check_hostname = False
ctx.verify_mode = ssl.CERT_NONE
try:
    urllib.request.urlopen(f'https://{fqdn}/version', timeout=5, context=ctx)
except Exception as e:
    print(f'error: cluster {cluster!r} not reachable at {fqdn}: {e}', file=sys.stderr)
    sys.exit(1)

import yaml  # PyYAML — available via system python on macOS

server = f'https://{fqdn}'
p = Path(kubeconfig_path)
p.parent.mkdir(parents=True, exist_ok=True)
cfg = yaml.safe_load(p.read_text()) if p.exists() else None
if not cfg:
    cfg = {'apiVersion': 'v1', 'kind': 'Config'}

def upsert(collection, name, value):
    items = cfg.get(collection) or []
    for i, item in enumerate(items):
        if item.get('name') == name:
            items[i] = value
            cfg[collection] = items
            return
    items.append(value)
    cfg[collection] = items

upsert('clusters', cluster, {'name': cluster, 'cluster': {'server': server, 'insecure-skip-tls-verify': True}})
upsert('users',    'netbird', {'name': 'netbird', 'user': {'token': 'none'}})
upsert('contexts', cluster, {'name': cluster, 'context': {'cluster': cluster, 'user': 'netbird', 'namespace': 'default'}})
cfg['current-context'] = cluster

p.write_text(yaml.dump(cfg, default_flow_style=False))
print(f'Switched to cluster {cluster!r}')
PYEOF
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
        cluster|clusters)
            get_clusters "$@"
            ;;
        kubeconfig|kc)
            get_kubeconfig "$@"
            ;;
        machine|machines|m)
            if [[ $# -gt 0 && "$1" != -* ]]; then
                get_machine "$@"
            else
                get_machines "$@"
            fi
            ;;
        snapshot|snapshots)
            get_snapshot "$@"
            ;;
*) echo "hsctl get: unknown resource '$resource'" >&2; get_usage ;;
    esac
}
