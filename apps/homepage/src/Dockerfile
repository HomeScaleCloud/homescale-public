FROM docker.io/library/nginx:alpine

RUN apk upgrade --no-cache && \
    mkdir -p /var/cache/nginx/{client_temp,proxy_temp,fastcgi_temp,uwsgi_temp,scgi_temp} && \
    mkdir -p /etc/nginx/ssl && \
    chown -R nginx:nginx /var/cache/nginx /etc/nginx /var/log/nginx /etc/nginx/ssl && \
    chmod -R 755 /etc/nginx /etc/nginx/ssl && \
    touch /var/run/nginx.pid && \
    chown -R nginx:nginx /var/run/nginx.pid /run/nginx.pid

COPY index.html /usr/share/nginx/html
RUN chown -R nginx:nginx /usr/share/nginx/html

USER nginx

LABEL org.opencontainers.image.source="https://github.com/HomeScaleCloud/homescale" \
      org.opencontainers.image.description="Simple homepage for homescale.cloud"
