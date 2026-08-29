FROM docker.io/nginxinc/nginx-unprivileged:1.31.4-alpine
# Patch OS packages ahead of upstream image rebuilds (e.g. openssl CVE-2026-14456)
USER root
RUN apk --no-cache upgrade libssl3 libcrypto3
USER nginx
COPY . /usr/share/nginx/html/
HEALTHCHECK --interval=30s --timeout=3s CMD wget -qO- http://localhost:8080/ || exit 1
