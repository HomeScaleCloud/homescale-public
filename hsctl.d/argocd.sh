#!/usr/bin/env bash
# hsctl argocd — ArgoCD operations

argocd_usage() {
    echo "Usage: hsctl argocd <subcommand> [args...]"
    echo ""
    echo "Subcommands:"
    echo "  login <cluster>   Log in to the ArgoCD instance for a cluster via SSO"
    exit 1
}

argocd_login() {
    local cluster="${1:-}"
    [[ -z "$cluster" ]] && { echo "Usage: hsctl argocd login <cluster>"; exit 1; }

    argocd login "argocd-server.argocd.${cluster}REDACTED" --sso
}

argocd_main() {
    [[ $# -eq 0 ]] && argocd_usage

    local sub="$1"; shift
    case "$sub" in
        login) argocd_login "$@" ;;
        *) echo "hsctl argocd: unknown subcommand '$sub'" >&2; argocd_usage ;;
    esac
}
