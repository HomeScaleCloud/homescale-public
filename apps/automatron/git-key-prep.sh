#!/usr/bin/env bash
# Copies the git deploy key to a writable volume owned by git-clone's UID (65533),
# and restores the trailing newline the stored Infisical value is missing — without
# it OpenSSH's new-format key parser fails with a generic "error in libcrypto".
# Runs as root: secret-mounted files are always root-owned, and sshd's strict
# key-perm check rejects any group/other bits, so fsGroup can't fix this instead.
set -euo pipefail

cp /etc/git-secret/sshPrivateKey /fixed/sshPrivateKey
if [ -n "$(tail -c1 /fixed/sshPrivateKey)" ]; then
    printf '\n' >> /fixed/sshPrivateKey
fi
chown 65533:65533 /fixed/sshPrivateKey
chmod 600 /fixed/sshPrivateKey
