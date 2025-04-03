#!/bin/bash
# Wrapper script for OpenTofu with 1Password secrets

export AWS_ACCESS_KEY_ID="op://github-actions/digitalocean/spaces-access-key-id"
export AWS_SECRET_ACCESS_KEY="op://github-actions/digitalocean/spaces-secret-access-key" #pragma: allowlist secret
export TF_VAR_cloudflare_token="op://common/cloudflare/credential"
export TF_VAR_cloudflare_account_id="op://common/cloudflare/account-id"
export TF_VAR_cloudflare_zone_id="op://common/cloudflare/zone-id"
export TF_VAR_digitalocean_token="op://github-actions/digitalocean/credential"
export TF_VAR_digitalocean_spaces_id="op://github-actions/digitalocean/spaces-access-key-id"
export TF_VAR_digitalocean_spaces_key="op://github-actions/digitalocean/spaces-secret-access-key"
export TF_VAR_vultr_token="op://github-actions/vultr/credential"

cd "$HOME/Repos/homescale/deploy/tofu"

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

/usr/bin/op run -- "$TOFU_BIN" "$@"
