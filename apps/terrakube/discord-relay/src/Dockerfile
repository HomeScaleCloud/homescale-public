FROM python:3.13-alpine
RUN adduser -D -u 1000 app
USER app
WORKDIR /app
COPY relay.py .
EXPOSE 8080
HEALTHCHECK --interval=30s --timeout=3s CMD wget -qO- http://localhost:8080/healthz || exit 1
CMD ["python3", "relay.py"]
LABEL org.opencontainers.image.source="https://github.com/HomeScaleCloud/homescale" \
      org.opencontainers.image.description="Translates Terrakube's generic webhook notifications into native Discord embeds with a View Run link button"
