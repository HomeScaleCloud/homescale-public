#!/usr/bin/env bash
# Called by pam_exec during sshd's auth phase (see pam-sshd). Resolves the
# connecting peer's Tailscale identity, requires it to be a REDACTED
# account matching the requested SSH username, and provisions that Unix
# account on first login.
set -euo pipefail

: "${PAM_RHOST:?}"
: "${PAM_USER:?}"

log() { echo "pam-tailscale-whois: $*" >&2; }

whois_json="$(tailscale whois --json "$PAM_RHOST" 2>/dev/null)" || {
  log "whois failed for $PAM_RHOST (not a tailnet peer?)"
  exit 1
}

login_name="$(jq -r '.UserProfile.LoginName // empty' <<<"$whois_json")"
if [ -z "$login_name" ]; then
  log "no LoginName in whois response for $PAM_RHOST"
  exit 1
fi

case "$login_name" in
  *@REDACTED) ;;
  *)
    log "rejecting identity outside REDACTED: $login_name"
    exit 1
    ;;
esac

local_part="${login_name%@*}"
if [ "$PAM_USER" != "$local_part" ]; then
  log "requested user '$PAM_USER' does not match identity '$login_name'"
  exit 1
fi

if ! id "$PAM_USER" >/dev/null 2>&1; then
  log "provisioning new account for $PAM_USER ($login_name)"
  useradd --create-home --shell /bin/bash "$PAM_USER"
fi

exit 0
