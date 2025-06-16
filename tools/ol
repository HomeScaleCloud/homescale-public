#!/usr/bin/env bash

if ! command -v omnictl &>/dev/null; then
    echo "Error: omnictl not found in PATH." >&2
    exit 1
fi

clusters=$(omnictl get clusters 2>/dev/null | awk 'NR>1 {print $3}')
cluster=$(echo "$clusters" | fzf --prompt="Select a cluster: " --height=10 --reverse)
omnictl kubeconfig --cluster "$cluster" --force

namespace=$(kubectl get namespaces -o jsonpath='{.items[*].metadata.name}' 2>/dev/null | tr " " "\n" | fzf --prompt="Select a namespace: " --height=10 --reverse)
namespace=${namespace:-default}
kubectl config set-context --current --namespace="$namespace" > /dev/null

echo "Switched to cluster '$cluster' and namespace '$namespace'."
