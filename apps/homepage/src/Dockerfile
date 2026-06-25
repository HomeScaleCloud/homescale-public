FROM docker.io/nginxinc/nginx-unprivileged:1.31.2-alpine
COPY index.html /usr/share/nginx/html/
USER nginx
HEALTHCHECK --interval=30s --timeout=3s CMD wget -qO- http://localhost:8080/ || exit 1

LABEL org.opencontainers.image.source="https://github.com/HomeScaleCloud/homescale" \
      org.opencontainers.image.description="Simple homepage for xxx"
