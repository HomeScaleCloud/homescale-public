#!/usr/bin/env bash
# hsctl argocd — ArgoCD operations

argocd_usage() {
    echo "Usage: hsctl argocd <subcommand> [args...]"
    echo ""
    echo "Subcommands:"
    echo "  login <cluster>   Log in to the ArgoCD instance for a cluster via SSO"
    echo "  open <cluster>    Open the ArgoCD UI for a cluster in the browser"
    exit 1
}

argocd_login() {
    local cluster="${1:-}"
    [[ -z "$cluster" ]] && { echo "Usage: hsctl argocd login <cluster>"; exit 1; }

    argocd login "argocd-server.argocd.${cluster}REDACTED" --sso
}

argocd_open() {
    local cluster="${1:-}"
    [[ -z "$cluster" ]] && { echo "Usage: hsctl argocd open <cluster>"; exit 1; }

    open "https://argocd-server.argocd.${cluster}REDACTED"
}

argocd_main() {
    [[ $# -eq 0 ]] && argocd_usage

    local sub="$1"; shift
    case "$sub" in
        login) argocd_login "$@" ;;
        open)  argocd_open  "$@" ;;
        *) echo "hsctl argocd: unknown subcommand '$sub'" >&2; argocd_usage ;;
    esac
}
