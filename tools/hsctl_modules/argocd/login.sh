#!/bin/bash
# Script to login to HomeScale ArgoCD instances quickly
argocd_login () {
    argocd --grpc-web login --sso argocd-${var.cluster}.${var.tailscale_tailnet}
}
