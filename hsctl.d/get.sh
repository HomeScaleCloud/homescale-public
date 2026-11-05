#!/usr/bin/env bash
# Query cluster, node and PIM resources; get_main sets HSCTL_OUTPUT.

get_usage() {
    echo "Usage: hsctl get <resource> [-o table|yaml|json|ansible] [flags...]"
    echo ""
    echo "Resources:"
    echo "  clusters                      List Kubernetes clusters reachable via Tailscale"
    echo "  kubeconfig <cluster> [flags]  Write kubeconfig context for a cluster; default is direct apiserver + OIDC"
    echo "      --break-glass                 Generate a short-lived TOPF admin kubeconfig"
    echo "  nodes [name]                  List Kubernetes nodes in the active kubectl context"
    echo "  snapshot <app>                List restic snapshots for an app"
    echo "  pimrole                     List your Entra directory role PIM eligibility/assignments"
    echo "  pimgroup                    List your Entra group PIM eligibility/assignments"
    echo "  pimazurerole --scope <s>    List your Azure resource RBAC PIM eligibility/assignments"
    echo "  pimapproval [role|group|azure] [--scope <s>]  List pending PIM approvals (yours and ones you can approve)"
    exit 1
}

_hsctl_kubernetes() {
    python3 -c "$(cat <<'KUBERNETES_PY'
"""Cluster discovery and node output for hsctl get."""
from concurrent.futures import ThreadPoolExecutor
from datetime import datetime, timezone
import json
import os
from pathlib import Path
import re
import subprocess
import sys


def command_json(command, timeout=None):
    return json.loads(subprocess.run(command, check=True, stdout=subprocess.PIPE, text=True, timeout=timeout).stdout)


def discover_clusters():
    status = command_json(['tailscale', 'status', '--json'], timeout=2)
    if status.get('BackendState') != 'Running':
        raise ValueError('Tailscale is not connected')
    names = set()
    peers = list((status.get('Peer') or {}).values()) + [status.get('Self') or {}]
    for peer in peers:
        tags = peer.get('Tags') or []
        if not peer.get('Online') or 'tag:k8s' not in tags:
            continue
        for tag in tags:
            if tag.startswith('tag:env-'):
                name = tag.removeprefix('tag:env-')
                if re.fullmatch(r'[a-z0-9](?:[a-z0-9-]*[a-z0-9])?', name):
                    names.add(name)
    with ThreadPoolExecutor(max_workers=8) as executor:
        return [cluster for cluster in executor.map(probe_cluster, sorted(names)) if cluster]


def probe_cluster(name):
    fqdn = f'k8s.api.{name}REDACTED'
    cluster = dict(name=name, fqdn=fqdn, k8s_version='-')
    try:
        response = subprocess.run([
            'curl', '--disable', '--silent', '--noproxy', '*', '--connect-timeout', '1',
            '--max-time', '2', '--retry', '0', '--write-out', '\n%{http_code}',
            f'https://{fqdn}/version',
        ], stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, text=True, timeout=3)
        if response.returncode:
            return None
        body, code = response.stdout.rsplit('\n', 1)
        if code == '200':
            cluster['k8s_version'] = json.loads(body)['gitVersion']
        elif code not in ('401', '403'):
            return None
    except (subprocess.TimeoutExpired, OSError, ValueError, KeyError):
        return None
    return cluster


def print_table(headers, rows):
    rows = [headers, *rows]
    widths = [max(len(str(row[index])) for row in rows) for index in range(len(headers))]
    for row in rows:
        print('  '.join(str(value).ljust(width) for value, width in zip(row, widths)).rstrip())


def age(timestamp):
    if not timestamp:
        return '-'
    seconds = int((datetime.now(timezone.utc) - datetime.fromisoformat(timestamp.replace('Z', '+00:00'))).total_seconds())
    if seconds < 0:
        return '<invalid>'
    if seconds < 120:
        return f'{seconds}s'
    minutes, seconds = divmod(seconds, 60)
    if minutes < 10:
        return f'{minutes}m' + (f'{seconds}s' if seconds else '')
    if minutes < 180:
        return f'{minutes}m'
    hours, minutes = divmod(minutes, 60)
    if hours < 8:
        return f'{hours}h' + (f'{minutes}m' if minutes else '')
    if hours < 48:
        return f'{hours}h'
    days, hours = divmod(hours, 24)
    if days < 8:
        return f'{days}d' + (f'{hours}h' if hours else '')
    if days < 730:
        return f'{days}d'
    years, days = divmod(days, 365)
    return f'{years}y' + (f'{days}d' if years < 8 and days else '')


def node_ip(node):
    return next((entry['address'] for entry in node.get('status', {}).get('addresses', [])
                 if entry['type'] == 'InternalIP'), None)


def topf_node_info(nodes):
    """Query only inventory nodes matching the active context's InternalIPs."""
    ips = {node_ip(node) for node in nodes} - {None}
    result = {}
    if not ips:
        return result
    for config in sorted(Path(os.environ['HSCTL_REPO_ROOT']).glob('clusters/*/topf.yaml')):
        cluster = config.parent.name
        try:
            inventory = command_json(['yq', '-o=json', '.', str(config)], timeout=5)
            hosts = [node['host'] for node in inventory.get('nodes', []) if node.get('ip') in ips]
            if not hosts:
                continue
            pattern = '^(' + '|'.join(re.escape(host) for host in hosts) + ')$'
            command = [str(Path(os.environ['HSCTL_ROOT']) / 'hsctl'), 'run', 'topf',
                       '--cluster', cluster, '--nodes-filter', pattern, 'nodes', '-o', 'yaml']
            response = subprocess.run(command, check=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                                      text=True, timeout=30)
            entries = json.loads(subprocess.run(['yq', '-p=yaml', '-o=json', '.'], input=response.stdout,
                                               check=True, stdout=subprocess.PIPE, text=True, timeout=5).stdout)
            for entry in entries or []:
                ip = entry.get('node', {}).get('ip')
                if ip in ips:
                    result[ip] = entry
        except (subprocess.CalledProcessError, subprocess.TimeoutExpired, ValueError, KeyError, OSError) as error:
            detail = error.stderr.strip() if isinstance(error, subprocess.CalledProcessError) and error.stderr else str(error)
            print(f'hsctl get nodes: TOPF status unavailable for {cluster}: {detail}', file=sys.stderr)
    return result


def node_record(node, topf):
    metadata = node['metadata']
    labels = metadata.get('labels') or {}
    status = node.get('status') or {}
    info = status.get('nodeInfo') or {}
    machine_status = topf.get('machinestatus') or {}
    talos_status = machine_status.get('status') or {}
    control_plane = any(key in labels for key in ['node-role.kubernetes.io/control-plane', 'node-role.kubernetes.io/master'])
    conditions = (talos_status.get('unmetConditions') or []) if topf else None
    return dict(name=metadata['name'], stage=machine_status.get('stage') or None, ready=talos_status.get('ready'),
                type='control-plane' if control_plane else 'worker',
                role=labels.get('REDACTED/role') or '-', ip=node_ip(node) or '-',
                image=info.get('osImage') or '-', schematic=topf.get('schematic') or None,
                kernel=info.get('kernelVersion') or '-', kubelet=info.get('kubeletVersion') or '-',
                runtime=info.get('containerRuntimeVersion') or '-', age=age(metadata.get('creationTimestamp')),
                unmet_conditions=[f'{condition["name"]}: {condition["reason"]}' for condition in conditions]
                if conditions is not None else None, error=topf.get('error') or None)


def print_nodes(records):
    headers = ['NAME', 'STAGE', 'READY', 'TYPE', 'ROLE', 'IP', 'IMAGE', 'SCHEMATIC', 'KERNEL',
               'KUBELET', 'RUNTIME', 'AGE', 'UNMET CONDITIONS', 'ERROR']
    rows = []
    for record in records:
        row = dict(record)
        row['ready'] = '✓' if record['ready'] is True else ('✗' if record['ready'] is False else '-')
        schematic = row['schematic']
        if schematic and len(schematic) > 8:
            row['schematic'] = schematic[:8] + '...'
        row['unmet_conditions'] = '; '.join(row['unmet_conditions'] or [])
        rows.append([' '.join(str(row[header.lower().replace(' ', '_')] or '-').split()) for header in headers])
    print_table(headers, rows)


def main():
    resource, output, *arguments = sys.argv[1:]
    if resource == 'nodes':
        if output not in ['table', 'json', 'yaml'] or len(arguments) > 1 or any(arg.startswith('-') for arg in arguments):
            raise ValueError('usage: hsctl get nodes [name] [-o table|json|yaml]')
        command = ['kubectl', 'get', 'nodes', *arguments]
        result = command_json([*command, '-o', 'json'])
        nodes = result.get('items', [result])
        topf = topf_node_info(nodes)
        records = [node_record(node, topf.get(node_ip(node), {})) for node in nodes]
        if output == 'table':
            print_nodes(records)
        elif output == 'yaml':
            subprocess.run(['yq', '-p=json', '-o=yaml', '.'], input=json.dumps(records), text=True, check=True)
        else:
            print(json.dumps(records, indent=2))
    elif resource == 'clusters':
        if arguments:
            raise ValueError('usage: hsctl get clusters [-o table|json|yaml|ansible]')
        clusters = discover_clusters()
        if output == 'table':
            print_table(['CLUSTER', 'API FQDN', 'K8S VERSION'],
                        [[cluster['name'], cluster['fqdn'], cluster['k8s_version']] for cluster in clusters])
        elif output == 'ansible':
            print(json.dumps({'clusters': {'hosts': [cluster['name'] for cluster in clusters]}, '_meta': {'hostvars': {}}}))
        elif output == 'yaml':
            subprocess.run(['yq', '-p=json', '-o=yaml', '.'], input=json.dumps(clusters), text=True, check=True)
        else:
            print(json.dumps(clusters, indent=2))


if __name__ == '__main__':
    try:
        main()
    except subprocess.CalledProcessError as error:
        if error.stderr:
            print(error.stderr.strip(), file=sys.stderr)
        sys.exit(error.returncode)
    except subprocess.TimeoutExpired:
        print('hsctl get: Tailscale status timed out', file=sys.stderr)
        sys.exit(1)
    except (ValueError, KeyError, OSError) as error:
        print(f'hsctl get: {error}', file=sys.stderr)
        sys.exit(1)
KUBERNETES_PY
)" "$@"
}

get_nodes() {
    _hsctl_kubernetes nodes "$HSCTL_OUTPUT" "$@"
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
    _hsctl_kubernetes clusters "$HSCTL_OUTPUT" "$@"
}

_hsctl_write_kubeconfig_direct() (
    local cluster="$1" kubeconfig="$2"
    local fqdn="k8s.api.${cluster}REDACTED"
    local user="${cluster}"

    _hsctl_resolve_oidc || exit 1

    mkdir -p "$(dirname "$kubeconfig")"

    # Convert through yq so merging needs only Python's standard library.
    umask 077
    local existing_json_file
    _hsctl_kubeconfig_workspace=$(mktemp -d "$(dirname "$kubeconfig")/.hsctl-kubeconfig.XXXXXX")
    trap 'rm -rf "$_hsctl_kubeconfig_workspace"' EXIT
    existing_json_file="$_hsctl_kubeconfig_workspace/existing.json"
    if [[ -f "$kubeconfig" ]]; then
        yq -p=yaml -o=json '.' "$kubeconfig" > "$existing_json_file"
    else
        echo '{}' > "$existing_json_file"
    fi

    python3 - "$cluster" "$fqdn" "$user" "$HSCTL_OIDC_ISSUER_URL" "$HSCTL_OIDC_CLIENT_ID" "$existing_json_file" <<'PYEOF' | yq -p=json -o=yaml '.' > "$_hsctl_kubeconfig_workspace/config"
import json, sys
from pathlib import Path

cluster, fqdn, user, issuer_url, client_id, existing_json_file = sys.argv[1:7]

server = f'https://{fqdn}'
cfg = json.loads(Path(existing_json_file).read_text()) or {}
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

upsert('clusters', cluster, {'name': cluster, 'cluster': {'server': server}})
upsert('users', user, {
    'name': user,
    'user': {
        'exec': {
            'apiVersion': 'client.authentication.k8s.io/v1',
            'command': 'kubectl',
            'args': [
                'oidc-login', 'get-token',
                f'--oidc-issuer-url={issuer_url}',
                f'--oidc-client-id={client_id}',
                '--oidc-extra-scope=profile,email,offline_access',
            ],
            'interactiveMode': 'IfAvailable',
            'provideClusterInfo': False,
        },
    },
})
upsert('contexts', cluster, {'name': cluster, 'context': {'cluster': cluster, 'user': user, 'namespace': 'default'}})
cfg['current-context'] = cluster

print(json.dumps(cfg))
PYEOF

    chmod 600 "$_hsctl_kubeconfig_workspace/config"
    mv "$_hsctl_kubeconfig_workspace/config" "$kubeconfig"
    echo "Switched to cluster '$cluster'"
)

get_kubeconfig() {
    local cluster="" mode="direct"
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --break-glass) mode="break-glass"; shift ;;
            -*) echo "hsctl get kubeconfig: unknown flag '$1'" >&2; get_usage ;;
            *) cluster="$1"; shift ;;
        esac
    done
    [[ -z "$cluster" ]] && { echo "Usage: hsctl get kubeconfig <cluster> [--break-glass]"; exit 1; }

    local kubeconfig="${KUBECONFIG:-$HOME/.kube/config}"
    kubeconfig="${kubeconfig%%:*}"

    case "$mode" in
        break-glass)
            (
                set -euo pipefail
                umask 077
                local workspace
                workspace=$(mktemp -d)
                trap 'rm -rf "$workspace"' EXIT
                "$HSCTL_REPO_ROOT/hsctl" run topf --cluster "$cluster" kubeconfig > "$workspace/admin"
                KUBECONFIG="$workspace/admin:$kubeconfig" kubectl config view --flatten --raw > "$workspace/merged"
                kubectl --kubeconfig="$workspace/merged" config use-context "topf@$cluster" >/dev/null
                mkdir -p "$(dirname "$kubeconfig")"
                install -m 600 "$workspace/merged" "$kubeconfig"
                echo "Switched to short-lived admin context 'topf@$cluster'"
            )
            ;;
        direct)
            local clusters
            clusters=$(HSCTL_OUTPUT=json get_clusters) || return 1
            jq -e --arg cluster "$cluster" 'any(.[]; .name == $cluster)' <<<"$clusters" >/dev/null || {
                hsctl_log_error "cluster '$cluster' is not reachable through Tailscale"
                return 1
            }
            _hsctl_write_kubeconfig_direct "$cluster" "$kubeconfig"
            ;;
    esac
}

HSCTL_PIM_GRAPH_SCOPES="https://graph.microsoft.com/RoleManagement.ReadWrite.Directory https://graph.microsoft.com/PrivilegedAccess.ReadWrite.AzureADGroup https://graph.microsoft.com/PrivilegedAccess.ReadWrite.AzureAD offline_access"
HSCTL_TENANT_ID="REDACTED"  # pragma: allowlist secret

_pim_require_deps() {
    command -v az &>/dev/null || { echo "hsctl: the Azure CLI is required (brew install azure-cli)" >&2; exit 1; }
    command -v jq &>/dev/null || { echo "hsctl: jq is required (brew install jq)" >&2; exit 1; }
    command -v curl &>/dev/null || { echo "hsctl: curl is required" >&2; exit 1; }
    command -v openssl &>/dev/null || { echo "hsctl: openssl is required" >&2; exit 1; }
    command -v python3 &>/dev/null || { echo "hsctl: python3 is required" >&2; exit 1; }
    command -v infisical &>/dev/null || { echo "hsctl: the infisical CLI is required (brew install infisical)" >&2; exit 1; }
    _pim_resolve_ids
}

_pim_resolve_ids() {
    [[ -n "${HSCTL_CLIENT_ID:-}" ]] && return 0

    HSCTL_CLIENT_ID=$(hsctl_infisical_call secrets get CLIENT_ID --silent --env=prod --path=/hsctl --plain) || {
        echo "hsctl: could not fetch CLIENT_ID from Infisical (/hsctl)" >&2
        exit 1
    }
    [[ -z "$HSCTL_CLIENT_ID" ]] && { echo "hsctl: CLIENT_ID at /hsctl in Infisical is empty" >&2; exit 1; }

    export HSCTL_TENANT_ID HSCTL_CLIENT_ID
}

_pim_ensure_signed_in() {
    local current_tenant
    current_tenant=$(az account show --query tenantId -o tsv 2>/dev/null) || current_tenant=""
    [[ "$current_tenant" == "$HSCTL_TENANT_ID" ]] && return 0

    hsctl_log_info "signing in to the HomeScale tenant"
    if ! az login --tenant "$HSCTL_TENANT_ID" >/dev/null; then
        echo "hsctl: sign-in failed" >&2
        return 1
    fi
}

HSCTL_PIM_KEYCHAIN_SERVICE="hsctl-graph"
HSCTL_PIM_KEYCHAIN_ACCOUNT="hsctl"

_pim_graph_token_file() {
    local dir="${XDG_CACHE_HOME:-$HOME/.cache}/hsctl"
    mkdir -p "$dir"
    printf '%s/pim-graph-token.json\n' "$dir"
}

_pim_graph_token_exists() {
    if command -v security &>/dev/null; then
        security find-generic-password -a "$HSCTL_PIM_KEYCHAIN_ACCOUNT" -s "$HSCTL_PIM_KEYCHAIN_SERVICE" &>/dev/null
    else
        [[ -f "$(_pim_graph_token_file)" ]]
    fi
}

_pim_graph_token_read() {
    if command -v security &>/dev/null; then
        security find-generic-password -a "$HSCTL_PIM_KEYCHAIN_ACCOUNT" -s "$HSCTL_PIM_KEYCHAIN_SERVICE" -w 2>/dev/null
    else
        cat "$(_pim_graph_token_file)" 2>/dev/null
    fi
}

_pim_save_graph_token() {
    local resp="$1"
    local expires_at; expires_at=$(( $(date +%s) + $(jq -r '.expires_in' <<< "$resp") - 60 ))
    local blob; blob=$(jq -nc --argjson r "$resp" --argjson exp "$expires_at" \
        '{access_token: $r.access_token, refresh_token: $r.refresh_token, expires_at: $exp}')
    if command -v security &>/dev/null; then
        security add-generic-password -a "$HSCTL_PIM_KEYCHAIN_ACCOUNT" -s "$HSCTL_PIM_KEYCHAIN_SERVICE" -w "$blob" -U &>/dev/null
        rm -f "$(_pim_graph_token_file)"
    else
        local f; f=$(_pim_graph_token_file)
        printf '%s' "$blob" > "$f"
        chmod 600 "$f"
    fi
}

_pim_graph_token_clear() {
    command -v security &>/dev/null && security delete-generic-password -a "$HSCTL_PIM_KEYCHAIN_ACCOUNT" -s "$HSCTL_PIM_KEYCHAIN_SERVICE" &>/dev/null
    rm -f "$(_pim_graph_token_file)"
}

_pim_urlencode() { jq -rn --arg v "$1" '$v|@uri'; }

_pim_graph_browser_login() {
    local code_verifier code_challenge state
    code_verifier=$(openssl rand -hex 32)
    code_challenge=$(printf '%s' "$code_verifier" | openssl dgst -sha256 -binary | openssl base64 | tr '+/' '-_' | tr -d '=')
    state=$(openssl rand -hex 16)

    local port_file result_file
    port_file=$(mktemp)
    result_file=$(mktemp)

    python3 - "$port_file" "$result_file" <<'PYEOF' &
import http.server, json, sys, urllib.parse

port_file, result_file = sys.argv[1], sys.argv[2]

class Handler(http.server.BaseHTTPRequestHandler):
    def log_message(self, *a):
        pass
    def do_GET(self):
        qs = urllib.parse.parse_qs(urllib.parse.urlparse(self.path).query)
        with open(result_file, "w") as f:
            json.dump({k: v[0] for k, v in qs.items()}, f)
        self.send_response(200)
        self.send_header("Content-Type", "text/html")
        self.end_headers()
        self.wfile.write(b"<html><body>Signed in \xe2\x80\x94 you can close this tab.</body></html>")

srv = http.server.HTTPServer(("127.0.0.1", 0), Handler)
with open(port_file, "w") as f:
    f.write(str(srv.server_address[1]))
srv.timeout = 300
srv.handle_request()
PYEOF
    local py_pid=$!

    local waited=0
    while [[ ! -s "$port_file" && $waited -lt 50 ]]; do sleep 0.1; waited=$((waited + 1)); done
    local port; port=$(cat "$port_file")
    [[ -z "$port" ]] && { hsctl_log_error "could not start local callback listener for Graph sign-in"; kill "$py_pid" 2>/dev/null; rm -f "$port_file" "$result_file"; return 1; }

    local redirect_uri="http://localhost:${port}"
    local authorize_url="https://login.microsoftonline.com/${HSCTL_TENANT_ID}/oauth2/v2.0/authorize"
    authorize_url+="?client_id=${HSCTL_CLIENT_ID}&response_type=code&response_mode=query"
    authorize_url+="&redirect_uri=$(_pim_urlencode "$redirect_uri")"
    authorize_url+="&scope=$(_pim_urlencode "$HSCTL_PIM_GRAPH_SCOPES")"
    authorize_url+="&code_challenge=${code_challenge}&code_challenge_method=S256&state=${state}"

    hsctl_log_info "Please continue authentication to Microsoft Entra in your browser"
    if command -v open &>/dev/null; then
        open "$authorize_url"
    elif command -v xdg-open &>/dev/null; then
        xdg-open "$authorize_url"
    else
        echo "Open this URL to sign in: $authorize_url" >&2
    fi

    wait "$py_pid"
    local qs; qs=$(cat "$result_file" 2>/dev/null)
    rm -f "$port_file" "$result_file"

    if [[ -z "$qs" ]]; then
        hsctl_log_error "Graph sign-in timed out waiting for browser redirect"
        return 1
    fi

    local err; err=$(jq -r '.error // empty' <<< "$qs")
    if [[ -n "$err" ]]; then
        hsctl_log_error "Graph sign-in failed: $(jq -r '.error_description // .error' <<< "$qs")"
        return 1
    fi

    local returned_state; returned_state=$(jq -r '.state // empty' <<< "$qs")
    [[ "$returned_state" == "$state" ]] || { hsctl_log_error "Graph sign-in failed: state mismatch (possible CSRF)"; return 1; }

    local code; code=$(jq -r '.code // empty' <<< "$qs")
    [[ -z "$code" ]] && { hsctl_log_error "Graph sign-in failed: no authorization code returned"; return 1; }

    local token_resp
    token_resp=$(curl -sg -X POST "https://login.microsoftonline.com/${HSCTL_TENANT_ID}/oauth2/v2.0/token" \
        --data-urlencode "client_id=$HSCTL_CLIENT_ID" \
        --data-urlencode "grant_type=authorization_code" \
        --data-urlencode "code=$code" \
        --data-urlencode "redirect_uri=$redirect_uri" \
        --data-urlencode "code_verifier=$code_verifier" \
        --data-urlencode "scope=$HSCTL_PIM_GRAPH_SCOPES")
    jq -e '.access_token' >/dev/null 2>&1 <<< "$token_resp" || { hsctl_log_error "Graph sign-in failed: $(jq -r '.error_description // .error // "token exchange failed"' <<< "$token_resp")"; return 1; }
    _pim_save_graph_token "$token_resp"
}

_pim_graph_refresh_token() {
    _pim_graph_token_exists || return 1
    local refresh_token; refresh_token=$(jq -r '.refresh_token // empty' <<< "$(_pim_graph_token_read)")
    [[ -z "$refresh_token" ]] && return 1

    local resp
    resp=$(curl -sg -X POST "https://login.microsoftonline.com/${HSCTL_TENANT_ID}/oauth2/v2.0/token" \
        --data-urlencode "grant_type=refresh_token" \
        --data-urlencode "client_id=$HSCTL_CLIENT_ID" \
        --data-urlencode "refresh_token=$refresh_token" \
        --data-urlencode "scope=$HSCTL_PIM_GRAPH_SCOPES")
    jq -e '.access_token' >/dev/null 2>&1 <<< "$resp" || return 1
    _pim_save_graph_token "$resp"
}

_pim_graph_access_token() {
    if _pim_graph_token_exists; then
        local data now expires_at
        data=$(_pim_graph_token_read)
        now=$(date +%s)
        expires_at=$(jq -r '.expires_at // 0' <<< "$data")
        [[ "$now" -lt "$expires_at" ]] && { jq -r '.access_token' <<< "$data"; return 0; }
        _pim_graph_refresh_token && { jq -r '.access_token' <<< "$(_pim_graph_token_read)"; return 0; }
    fi
    _pim_graph_browser_login || return 1
    jq -r '.access_token' <<< "$(_pim_graph_token_read)"
}

_pim_graph_rest() {
    local method="$1" url="$2" body="${3:-}"
    local token; token=$(_pim_graph_access_token) || return 1

    local out code resp_body
    if [[ -n "$body" ]]; then
        out=$(curl -sg -w $'\n%{http_code}' -X "$method" "$url" \
            -H "Authorization: Bearer $token" -H "Content-Type: application/json" -d "$body")
    else
        out=$(curl -sg -w $'\n%{http_code}' -X "$method" "$url" -H "Authorization: Bearer $token")
    fi
    code=$(tail -n1 <<< "$out")
    resp_body=$(sed '$d' <<< "$out")

    if [[ "$code" -ge 400 ]]; then
        hsctl_log_error "graph $method $url failed ($code): $resp_body"
        return 1
    fi
    printf '%s\n' "$resp_body"
}

_pim_fetch_parallel() {
    _pim_graph_access_token >/dev/null || return 1
    local pids=() rc=0
    while [[ $# -gt 0 ]]; do
        local outfile="$1" url="$2"; shift 2
        _pim_graph_rest GET "$url" > "$outfile" &
        pids+=("$!")
    done
    local pid
    for pid in "${pids[@]}"; do wait "$pid" || rc=1; done
    return "$rc"
}

_pim_normalize_scope() {
    local s="$1"
    [[ "$s" == /* ]] && printf '%s\n' "$s" || printf '/subscriptions/%s\n' "$s"
}

_pim_rest() {
    _pim_ensure_signed_in || return 1
    local method="$1" url="$2" body="${3:-}"
    local errfile out rc
    errfile=$(mktemp)
    if [[ -n "$body" ]]; then
        out=$(az rest --method "$method" --url "$url" --body "$body" 2>"$errfile")
    else
        out=$(az rest --method "$method" --url "$url" 2>"$errfile")
    fi
    rc=$?
    if [[ $rc -ne 0 ]]; then
        hsctl_log_error "az rest $method $url failed: $(cat "$errfile")"
        rm -f "$errfile"
        return 1
    fi
    rm -f "$errfile"
    printf '%s\n' "$out"
}

get_pimrole() {
    _pim_require_deps
    local elig_f active_f; elig_f=$(mktemp); active_f=$(mktemp)
    _pim_fetch_parallel \
        "$elig_f" "https://graph.microsoft.com/v1.0/roleManagement/directory/roleEligibilityScheduleInstances/filterByCurrentUser(on='principal')?\$expand=roleDefinition" \
        "$active_f" "https://graph.microsoft.com/v1.0/roleManagement/directory/roleAssignmentScheduleInstances/filterByCurrentUser(on='principal')?\$expand=roleDefinition" \
        || { rm -f "$elig_f" "$active_f"; return 1; }
    local elig active; elig=$(<"$elig_f"); active=$(<"$active_f")
    rm -f "$elig_f" "$active_f"

    case "$HSCTL_OUTPUT" in
        table)
            printf "%-10s  %-40s  %-10s  %s\n" "STATUS" "ROLE" "TYPE" "END TIME"
            jq -r '.value[] | [.roleDefinition.displayName, (.endDateTime // "permanent"), .memberType] | @tsv' <<< "$elig" | \
                while IFS=$'\t' read -r role end mtype; do printf "%-10s  %-40s  %-10s  %s\n" "eligible" "$role" "$mtype" "$end"; done
            jq -r '.value[] | [.roleDefinition.displayName, (.endDateTime // "permanent"), .assignmentType] | @tsv' <<< "$active" | \
                while IFS=$'\t' read -r role end atype; do printf "%-10s  %-40s  %-10s  %s\n" "active" "$role" "$atype" "$end"; done
            ;;
        json) jq -n --argjson e "$(jq '.value' <<< "$elig")" --argjson a "$(jq '.value' <<< "$active")" '{eligible:$e, active:$a}' ;;
        yaml) jq -n --argjson e "$(jq '.value' <<< "$elig")" --argjson a "$(jq '.value' <<< "$active")" '{eligible:$e, active:$a}' | yq -p json -o yaml ;;
    esac
}

get_pimgroup() {
    _pim_require_deps
    local elig_f active_f; elig_f=$(mktemp); active_f=$(mktemp)
    _pim_fetch_parallel \
        "$elig_f" "https://graph.microsoft.com/v1.0/identityGovernance/privilegedAccess/group/eligibilityScheduleInstances/filterByCurrentUser(on='principal')?\$expand=group" \
        "$active_f" "https://graph.microsoft.com/v1.0/identityGovernance/privilegedAccess/group/assignmentScheduleInstances/filterByCurrentUser(on='principal')?\$expand=group" \
        || { rm -f "$elig_f" "$active_f"; return 1; }
    local elig active; elig=$(<"$elig_f"); active=$(<"$active_f")
    rm -f "$elig_f" "$active_f"

    case "$HSCTL_OUTPUT" in
        table)
            printf "%-10s  %-40s  %-10s  %s\n" "STATUS" "GROUP" "ACCESS" "END TIME"
            jq -r '.value[] | [.group.displayName, (.endDateTime // "permanent"), .accessId] | @tsv' <<< "$elig" | \
                while IFS=$'\t' read -r group end access; do printf "%-10s  %-40s  %-10s  %s\n" "eligible" "$group" "$access" "$end"; done
            jq -r '.value[] | [.group.displayName, (.endDateTime // "permanent"), .accessId] | @tsv' <<< "$active" | \
                while IFS=$'\t' read -r group end access; do printf "%-10s  %-40s  %-10s  %s\n" "active" "$group" "$access" "$end"; done
            ;;
        json) jq -n --argjson e "$(jq '.value' <<< "$elig")" --argjson a "$(jq '.value' <<< "$active")" '{eligible:$e, active:$a}' ;;
        yaml) jq -n --argjson e "$(jq '.value' <<< "$elig")" --argjson a "$(jq '.value' <<< "$active")" '{eligible:$e, active:$a}' | yq -p json -o yaml ;;
    esac
}

get_pimazurerole() {
    _pim_require_deps
    local scope=""
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --scope) scope="$2"; shift 2 ;;
            *) echo "hsctl get pimazurerole: unknown flag '$1'" >&2; exit 1 ;;
        esac
    done
    [[ -z "$scope" ]] && { echo "Usage: hsctl get pimazurerole --scope <arm-scope>" >&2; exit 1; }
    scope=$(_pim_normalize_scope "$scope")

    local elig active
    elig=$(_pim_rest GET "https://management.azure.com${scope}/providers/Microsoft.Authorization/roleEligibilityScheduleInstances?api-version=2020-10-01-preview&\$filter=asTarget()") || return 1
    active=$(_pim_rest GET "https://management.azure.com${scope}/providers/Microsoft.Authorization/roleAssignmentScheduleInstances?api-version=2020-10-01-preview&\$filter=asTarget()") || return 1

    case "$HSCTL_OUTPUT" in
        table)
            printf "%-10s  %-40s  %s\n" "STATUS" "ROLE" "END TIME"
            jq -r '.value[] | [.properties.expandedProperties.roleDefinition.displayName, (.properties.endDateTime // "permanent")] | @tsv' <<< "$elig" | \
                while IFS=$'\t' read -r role end; do printf "%-10s  %-40s  %s\n" "eligible" "$role" "$end"; done
            jq -r '.value[] | [.properties.expandedProperties.roleDefinition.displayName, (.properties.endDateTime // "permanent")] | @tsv' <<< "$active" | \
                while IFS=$'\t' read -r role end; do printf "%-10s  %-40s  %s\n" "active" "$role" "$end"; done
            ;;
        json) jq -n --argjson e "$(jq '.value' <<< "$elig")" --argjson a "$(jq '.value' <<< "$active")" '{eligible:$e, active:$a}' ;;
        yaml) jq -n --argjson e "$(jq '.value' <<< "$elig")" --argjson a "$(jq '.value' <<< "$active")" '{eligible:$e, active:$a}' | yq -p json -o yaml ;;
    esac
}

_pim_approve_list_combined() {
    local approver_url="$1" mine_url="$2"
    local pending; pending=$(_pim_urlencode "status eq 'PendingApproval'")
    local approver_f mine_f; approver_f=$(mktemp); mine_f=$(mktemp)
    _pim_fetch_parallel \
        "$approver_f" "${approver_url}?\$filter=${pending}&\$expand=principal" \
        "$mine_f" "${mine_url}?\$filter=${pending}&\$expand=principal" \
        || { rm -f "$approver_f" "$mine_f"; return 1; }
    local as_approver as_mine; as_approver=$(<"$approver_f"); as_mine=$(<"$mine_f")
    rm -f "$approver_f" "$mine_f"
    jq -n --argjson a "$(jq '.value' <<< "$as_approver")" --argjson m "$(jq '.value' <<< "$as_mine")" \
        '($a | map(. + {role:"approver"})) + ($m | map(. + {role:"requestor"}))'
}

_get_pimapproval_role() {
    local combined
    combined=$(_pim_approve_list_combined \
        "https://graph.microsoft.com/v1.0/roleManagement/directory/roleAssignmentScheduleRequests/filterByCurrentUser(on='approver')" \
        "https://graph.microsoft.com/v1.0/roleManagement/directory/roleAssignmentScheduleRequests/filterByCurrentUser(on='principal')") || return 1
    case "$HSCTL_OUTPUT" in
        table)
            printf "%-38s  %-16s  %-10s  %-32s  %s\n" "REQUEST ID" "STATUS" "ROLE" "REQUESTER" "JUSTIFICATION"
            jq -r '.[] | [.id, .status, .role, ((.principal.displayName // "-") + " <" + (.principal.userPrincipalName // .principal.mail // "-") + ">"), (.justification // "-")] | @tsv' <<< "$combined" | \
                while IFS=$'\t' read -r id req_status req_role requester just; do printf "%-38s  %-16s  %-10s  %-32s  %s\n" "$id" "$req_status" "$req_role" "$requester" "$just"; done
            ;;
        json) printf '%s\n' "$combined" ;;
        yaml) printf '%s\n' "$combined" | yq -p json -o yaml ;;
    esac
}

_get_pimapproval_group() {
    local combined
    combined=$(_pim_approve_list_combined \
        "https://graph.microsoft.com/v1.0/identityGovernance/privilegedAccess/group/assignmentScheduleRequests/filterByCurrentUser(on='approver')" \
        "https://graph.microsoft.com/v1.0/identityGovernance/privilegedAccess/group/assignmentScheduleRequests/filterByCurrentUser(on='principal')") || return 1
    case "$HSCTL_OUTPUT" in
        table)
            printf "%-38s  %-16s  %-10s  %-32s  %s\n" "REQUEST ID" "STATUS" "ROLE" "REQUESTER" "JUSTIFICATION"
            jq -r '.[] | [.id, .status, .role, ((.principal.displayName // "-") + " <" + (.principal.userPrincipalName // .principal.mail // "-") + ">"), (.justification // "-")] | @tsv' <<< "$combined" | \
                while IFS=$'\t' read -r id req_status req_role requester just; do printf "%-38s  %-16s  %-10s  %-32s  %s\n" "$id" "$req_status" "$req_role" "$requester" "$just"; done
            ;;
        json) printf '%s\n' "$combined" ;;
        yaml) printf '%s\n' "$combined" | yq -p json -o yaml ;;
    esac
}

_get_pimapproval_azure() {
    local scope; scope=$(_pim_normalize_scope "$1")
    local resp
    resp=$(_pim_rest GET "https://management.azure.com${scope}/providers/Microsoft.Authorization/roleAssignmentApprovals?api-version=2021-01-01-preview") || return 1
    case "$HSCTL_OUTPUT" in
        table)
            printf "%-38s  %-12s  %s\n" "APPROVAL ID" "STATUS" "STAGE IDs"
            jq -r '.value[] | [.id, .properties.status, ([.properties.stages[]? | .id] | join(","))] | @tsv' <<< "$resp" | \
                while IFS=$'\t' read -r id status stages; do printf "%-38s  %-12s  %s\n" "$id" "$status" "${stages:--}"; done
            ;;
        json) jq '.value' <<< "$resp" ;;
        yaml) jq '.value' <<< "$resp" | yq -p json -o yaml ;;
    esac
}

get_pimapproval() {
    _pim_require_deps
    local type="" scope=""
    [[ $# -gt 0 && "$1" != -* ]] && { type="$1"; shift; }
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --scope) scope="$2"; shift 2 ;;
            *) echo "hsctl get pimapproval: unknown flag '$1'" >&2; exit 1 ;;
        esac
    done

    case "$type" in
        role|roles) _get_pimapproval_role ;;
        group|groups) _get_pimapproval_group ;;
        azure)
            [[ -z "$scope" ]] && { echo "hsctl get pimapproval azure: --scope is required" >&2; exit 1; }
            _get_pimapproval_azure "$scope"
            ;;
        "") _get_pimapproval_role; _get_pimapproval_group ;;
        *) echo "hsctl get pimapproval: unknown type '$type' (expected role, group, or azure)" >&2; exit 1 ;;
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
        cluster|clusters)
            get_clusters "$@"
            ;;
        kubeconfig|kc)
            get_kubeconfig "$@"
            ;;
        node|nodes|no)
            get_nodes "$@"
            ;;
        snapshot|snapshots)
            get_snapshot "$@"
            ;;
        pimrole|pimroles)
            get_pimrole "$@"
            ;;
        pimgroup|pimgroups)
            get_pimgroup "$@"
            ;;
        pimazurerole|pimazureroles)
            get_pimazurerole "$@"
            ;;
        pimapproval|pimapprovals)
            get_pimapproval "$@"
            ;;
*) echo "hsctl get: unknown resource '$resource'" >&2; get_usage ;;
    esac
}
