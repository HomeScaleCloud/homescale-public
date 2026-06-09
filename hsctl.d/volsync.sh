#!/usr/bin/env bash
# hsctl volsync — VolumeSync/restic operations

volsync_usage() {
    echo "Usage: hsctl volsync <subcommand> [args...]"
    echo ""
    echo "Subcommands:"
    echo "  snapshot list <app>   List restic snapshots for an app"
    exit 1
}

volsync_snapshot_list() {
    local app="${1:-}"
    [[ -z "$app" ]] && { echo "Usage: hsctl volsync snapshot list <app>"; exit 1; }

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

volsync_main() {
    [[ $# -eq 0 ]] && volsync_usage

    local sub="$1"; shift
    case "$sub" in
        snapshot)
            [[ $# -eq 0 ]] && volsync_usage
            local subsub="$1"; shift
            case "$subsub" in
                list) volsync_snapshot_list "$@" ;;
                *) echo "hsctl volsync snapshot: unknown subcommand '$subsub'" >&2; volsync_usage ;;
            esac
            ;;
        *) echo "hsctl volsync: unknown subcommand '$sub'" >&2; volsync_usage ;;
    esac
}
