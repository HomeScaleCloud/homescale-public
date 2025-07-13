#!/bin/bash
# Script to login to HomeScale ArgoCD instances quickly
argocd_login () {
    argocd --grpc-web login --sso argocd.$1.homescale.cloud
}
