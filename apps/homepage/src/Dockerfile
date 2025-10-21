FROM docker.io/library/nginx:alpine
RUN apk upgrade --no-cache
COPY index.html /usr/share/nginx/html

LABEL org.opencontainers.image.source=https://github.com/HomeScaleCloud/homescale
LABEL org.opencontainers.image.description="Simple homepage for homescale.cloud"
