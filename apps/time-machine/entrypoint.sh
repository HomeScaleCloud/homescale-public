#!/bin/sh
set -e

: "${TM_USERNAME:?TM_USERNAME is required}"
: "${TM_PASSWORD:?TM_PASSWORD is required}"

TM_UID="${TM_UID:-1000}"
TM_GID="${TM_GID:-1000}"
TM_VOLUME_NAME="${TM_VOLUME_NAME:-Time Machine}"
TM_DIR="/opt/timemachine"
IFACE="net1"

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

# Wait for the Multus macvlan interface before starting Avahi
until ip link show "${IFACE}" >/dev/null 2>&1; do
    echo "Waiting for ${IFACE}..."
    sleep 1
done

cat > /etc/avahi/avahi-daemon.conf << CONF
[server]
host-name=time-machine
allow-interfaces=${IFACE}
use-ipv4=yes
use-ipv6=no
[wide-area]
[publish]
publish-workstation=no
[reflector]
[rlimits]
CONF

mkdir -p /etc/avahi/services
cat > /etc/avahi/services/timemachine.service << XML
<?xml version="1.0" standalone='no'?>
<!DOCTYPE service-group SYSTEM "avahi-service.dtd">
<service-group>
  <name replace-wildcards="yes">%h</name>
  <service>
    <type>_adisk._tcp</type>
    <port>445</port>
    <txt-record>sys=waMa=0,adVF=0x100</txt-record>
    <txt-record>dk0=adVN=${TM_VOLUME_NAME},adVF=0x82</txt-record>
  </service>
  <service>
    <type>_smb._tcp</type>
    <port>445</port>
  </service>
</service-group>
XML

mkdir -p /run/dbus
dbus-uuidgen > /var/lib/dbus/machine-id 2>/dev/null || true
dbus-daemon --system --nofork &
sleep 1

avahi-daemon --no-drop-root &

exec smbd --foreground --no-process-group --configfile=/etc/samba/smb.conf
