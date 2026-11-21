FROM python:3.13-alpine
RUN rm -rf /usr/local/lib/python3.13/site-packages/pip* \
    && rm -f /usr/local/bin/pip /usr/local/bin/pip3 /usr/local/bin/pip3.13
RUN adduser -D -u 1000 app
USER app
WORKDIR /app
COPY relay.py .
EXPOSE 8080
HEALTHCHECK --interval=30s --timeout=3s CMD wget -qO- http://localhost:8080/healthz || exit 1
CMD ["python3", "relay.py"]
LABEL org.opencontainers.image.source="https://github.com/HomeScaleCloud/homescale" \
      org.opencontainers.image.description="Translates Terrakube's generic webhook notifications into native Discord embeds with a View Run link button"
