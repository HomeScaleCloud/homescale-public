FROM alpine:3.21.3

RUN apk add --no-cache samba samba-common-tools

COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

VOLUME ["/opt/timemachine"]
EXPOSE 445

ENTRYPOINT ["/entrypoint.sh"]
