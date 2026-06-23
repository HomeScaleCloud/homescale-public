#!/bin/sh
set -e

: "${TM_USERNAME:?TM_USERNAME is required}"
: "${TM_PASSWORD:?TM_PASSWORD is required}"

TM_UID="${TM_UID:-1000}"
TM_GID="${TM_GID:-1000}"
TM_VOLUME_NAME="${TM_VOLUME_NAME:-Time Machine}"
TM_DIR="/opt/timemachine"

addgroup -g "${TM_GID}" -S "${TM_USERNAME}" 2>/dev/null || true
adduser  -u "${TM_UID}" -G "${TM_USERNAME}" -S -D "${TM_USERNAME}" 2>/dev/null || true

mkdir -p "${TM_DIR}"
chown "${TM_USERNAME}:${TM_USERNAME}" "${TM_DIR}"

cat > /etc/samba/smb.conf << CONF
[global]
    workgroup = WORKGROUP
    server string = Time Machine
    security = user
    passdb backend = tdbsam
    log level = 1
    max log size = 0
    vfs objects = catia fruit streams_xattr
    fruit:metadata = stream
    fruit:model = TimeCapsule8,119
    fruit:posix_rename = yes
    fruit:veto_appledouble = no
    fruit:wipe_intentionally_left_blank_rfork = yes
    fruit:delete_empty_adfiles = yes

[${TM_VOLUME_NAME}]
    path = ${TM_DIR}
    valid users = ${TM_USERNAME}
    browseable = yes
    writeable = yes
    create mask = 0600
    directory mask = 0700
    fruit:time machine = yes
    fruit:time machine max size = 0
CONF

printf '%s\n%s\n' "${TM_PASSWORD}" "${TM_PASSWORD}" | smbpasswd -a -s "${TM_USERNAME}"

exec smbd --foreground --no-process-group --configfile=/etc/samba/smb.conf
