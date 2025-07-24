#!/usr/bin/env bash
# hsctl_modules/tf.sh
# Wrapper script for Terraform with 1Password secrets
set -euo pipefail

export TF_VAR_op_service_account_token="op://github-actions/onepassword/credential"

check_op_logged_in() {
  SESSION_FILE="$HOME/.config/hsctl/op_session"

  # Use cached session if available
  if [[ -f "$SESSION_FILE" ]]; then
    export OP_SESSION_my="$(<"$SESSION_FILE")"
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

    printf "%s" "$SESSION_TOKEN" > "$SESSION_FILE"
    chmod 600 "$SESSION_FILE"
    export OP_SESSION_my="$SESSION_TOKEN"
  fi
}

tf() {
  check_op_logged_in

  cd "$HOME/Repos/homescale/infra/terraform"

  TF_BIN=""
  for path in "/usr/bin/terraform" "/home/linuxbrew/.linuxbrew/bin/terraform"; do
    if [[ -x "$path" ]]; then
      TF_BIN="$path"
      break
    fi
  done

  if [[ -z "$TF_BIN" ]]; then
    echo "Error: Terraform binary not found." >&2
    exit 1
  fi

  # Pass all args (e.g. init, plan, apply, etc.) through to terraform
  /usr/bin/op run -- "$TF_BIN" "$@"
}
