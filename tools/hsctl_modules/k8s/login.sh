#!/usr/bin/env bash
set -euo pipefail

k8s_login() {
    for cmd in tailscale jq fzf kubectl; do
        if ! command -v "$cmd" &>/dev/null; then
            echo "Error: '$cmd' not found in PATH." >&2
            exit 1
        fi
    done

    CONFIG_PATH="$HOME/.kube/config-homescale"
    export KUBECONFIG="$CONFIG_PATH"

    mkdir -p "$(dirname "$CONFIG_PATH")"
    touch "$CONFIG_PATH"

    # Pull Tailscale k8s-api-tagged nodes
    cluster_lines=$(tailscale status --json |
        jq -r '.Peer[] | select(.Tags[]? == "tag:k8s-api") | .DNSName' |
        sed 's/\.$//' |
        awk -F. '{ short=$1; gsub(/^k8s-/, "", short); print short "\t" $0 }' |
        sort -u)

    [[ -z "$cluster_lines" ]] && { echo "No clusters found with tag:k8s-api" >&2; exit 1; }

    if [[ -n "${1:-}" ]]; then
        short_name="$1"
        fqdn=$(awk -v short="$short_name" '$1 == short { print $2 }' <<< "$cluster_lines")

        if [[ -z "$fqdn" ]]; then
            echo "Error: Cluster '$short_name' not found in Tailscale list." >&2
            exit 1
        fi

        if [[ -n "${2:-}" ]]; then
            namespace="$2"
        else
            # Prompt for namespace using fuzzy finder
            namespace=$(kubectl --kubeconfig="$CONFIG_PATH" --server="https://$fqdn" --insecure-skip-tls-verify=true \
                get namespaces -o jsonpath='{.items[*].metadata.name}' 2>/dev/null |
                tr " " "\n" |
                fzf --prompt="Select a namespace: " --height=10 --reverse)
            namespace=${namespace:-default}
        fi
    else
        # Fuzzy select both cluster and namespace
        selection=$(echo "$cluster_lines" | fzf --prompt="Select a cluster: " --height=10 --reverse)
        [[ -z "$selection" ]] && { echo "No cluster selected." >&2; exit 1; }

        short_name=$(cut -f1 <<< "$selection")
        fqdn=$(cut -f2 <<< "$selection")

        namespace=$(kubectl --kubeconfig="$CONFIG_PATH" --server="https://$fqdn" --insecure-skip-tls-verify=true \
            get namespaces -o jsonpath='{.items[*].metadata.name}' 2>/dev/null |
            tr " " "\n" |
            fzf --prompt="Select a namespace: " --height=10 --reverse)
        namespace=${namespace:-default}
    fi

    cluster_name="$short_name"
    context_name="$short_name"

    kubectl config --kubeconfig="$CONFIG_PATH" set-cluster "$cluster_name" \
        --server="https://$fqdn" \
        --insecure-skip-tls-verify=true >/dev/null

    kubectl config --kubeconfig="$CONFIG_PATH" set-credentials tailscale-auth \
        --token=unused >/dev/null

    kubectl config --kubeconfig="$CONFIG_PATH" set-context "$context_name" \
        --cluster="$cluster_name" \
        --user=tailscale-auth >/dev/null

    kubectl config --kubeconfig="$CONFIG_PATH" use-context "$context_name" >/dev/null

    kubectl config --kubeconfig="$CONFIG_PATH" set-context --current --namespace="$namespace" >/dev/null

    echo "Switched to cluster '$short_name' and namespace '$namespace'."
}
