#!/bin/bash
# Wrapper script for OpenTofu with 1Password secrets

export AWS_ACCESS_KEY_ID="op://ci-cd/digitalocean/spaces-access-key-id"
export AWS_SECRET_ACCESS_KEY="op://ci-cd/digitalocean/spaces-secret-access-key" #pragma: allowlist secret
export TF_VAR_cloudflare_token="op://ci-cd/cloudflare/credential"
export TF_VAR_cloudflare_account_id="op://ci-cd/cloudflare/account-id"
export TF_VAR_cloudflare_zone_id="op://ci-cd/cloudflare/zone-id"
export TF_VAR_digitalocean_token="op://ci-cd/digitalocean/credential"
export TF_VAR_vultr_token="op://ci-cd/vultr/credential"

cd "$HOME/Repos/morrislan/infra/tofu"

TOFU_BIN=""
for path in "/usr/bin/tofu" "/home/linuxbrew/.linuxbrew/bin/tofu"; do
    if [ -x "$path" ]; then
        TOFU_BIN="$path"
        break
    fi
done

if [ -z "$TOFU_BIN" ]; then
    echo "Error: OpenTofu binary not found." >&2
    exit 1
fi

op run -- "$TOFU_BIN" "$@"
