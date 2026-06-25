FROM docker.io/nginxinc/nginx-unprivileged:1.31.2-alpine
COPY . /usr/share/nginx/html/
USER nginx
HEALTHCHECK --interval=30s --timeout=3s CMD wget -qO- http://localhost:8080/ || exit 1
