#!/usr/bin/env bash
# Prepares the git deploy key for git-clone's non-root UID. Runs as root (only this
# container needs to) because k8s secret-mounted files are always root-owned — there's
# no way to get kubelet to mint them owned by an arbitrary non-root UID — and sshd's
# strict key-perm check rejects any group/other permission bits, so widening access via
# fsGroup instead (group-readable) doesn't work either. Copies the key into a writable
# volume, hands ownership to git-clone's actual UID (65533, git-sync's own non-root
# UID), and restores the trailing newline after "-----END OPENSSH PRIVATE KEY-----"
# that the stored Infisical value is missing but OpenSSH's new-format key parser
# needs — without it, ssh fails with a generic "error in libcrypto" (confirmed
# directly: identical content with the newline restored authenticates fine, without it
# it doesn't, regardless of which user reads it).
set -euo pipefail

cp /etc/git-secret/sshPrivateKey /fixed/sshPrivateKey
if [ -n "$(tail -c1 /fixed/sshPrivateKey)" ]; then
    printf '\n' >> /fixed/sshPrivateKey
fi
chown 65533:65533 /fixed/sshPrivateKey
chmod 600 /fixed/sshPrivateKey
