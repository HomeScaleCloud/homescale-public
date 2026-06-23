FROM alpine:3.22

RUN apk add --no-cache samba samba-common-tools avahi dbus

COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

VOLUME ["/opt/timemachine"]
EXPOSE 445

ENTRYPOINT ["/entrypoint.sh"]
