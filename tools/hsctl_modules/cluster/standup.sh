#!/bin/bash
# Script to provision/standup k8s clusters
set -e

if [ "$#" -ne 1 ]; then
    echo "Usage: $0 <clusterName>"
    exit 1
fi

CLUSTER_NAME=$1

check_op_logged_in() {
    SESSION_FILE="$HOME/.config/hsctl/op_session"

    # Use cached session if available
    if [[ -f "$SESSION_FILE" ]]; then
        export OP_SESSION_my="$(cat "$SESSION_FILE")"
    fi

    # If not signed in, do so and cache session
    if ! /usr/bin/op whoami &>/dev/null; then
        echo "🔐 Signing in to 1Password..."
        mkdir -p "$(dirname "$SESSION_FILE")"
        SESSION_TOKEN=$(/usr/bin/op signin --raw)

        if [[ -z "$SESSION_TOKEN" ]]; then
        echo "❌ Failed to sign in to 1Password." >&2
        exit 1
        fi

        echo "$SESSION_TOKEN" > "$SESSION_FILE"
        chmod 600 "$SESSION_FILE"
        export OP_SESSION_my="$SESSION_TOKEN"
    fi
}
cluster_standup () {
    kubectl create ns argocd
    kubectl apply -n argocd -k apps/argocd/overlays/$CLUSTER_NAME/manifests
    kubectl apply -n argocd -f clusters/$CLUSTER_NAME
    check_op_logged_in

    if ! /usr/bin/op vault get "$CLUSTER_NAME" >/dev/null 2>&1; then
        echo "Vault $CLUSTER_NAME does not exist. Creating..."
        /usr/bin/op vault create "$CLUSTER_NAME"
    fi

    RESPONSE=$(/usr/bin/op connect server create "$CLUSTER_NAME" --vaults "$CLUSTER_NAME,common")
    CONNECT_CREDENTIALS_FILE=$(echo "$RESPONSE" | grep "Credentials file" | awk '{print $NF}')

    OPERATOR_TOKEN=$(/usr/bin/op connect token create "$CLUSTER_NAME" --server "$CLUSTER_NAME" --vault "$CLUSTER_NAME" --vault "common")

    CONNECT_CREDENTIALS=$(base64 -w 0 "$CONNECT_CREDENTIALS_FILE")

    /usr/bin/op item create --vault "$CLUSTER_NAME" --category "API Credential" --title "onepassword" \
        operator-token="$OPERATOR_TOKEN" connect-credentials="$CONNECT_CREDENTIALS"

    rm $CONNECT_CREDENTIALS_FILE

    kubectl create ns onepassword
    kubectl create secret generic "op-onepassword" \
    --from-literal=operator-token="$OPERATOR_TOKEN" \
    --from-literal=connect-credentials="$CONNECT_CREDENTIALS" \
    -n onepassword
    kubectl delete pods --all -n onepassword
    kubectl delete pods --all -n argocd
}
