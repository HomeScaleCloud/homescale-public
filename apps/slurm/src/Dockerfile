FROM ghcr.io/slinkyproject/login:26.05-ubuntu26.04

# Only the `tailscale` CLI is needed here (for `tailscale whois`) — the
# daemon runs in a sidecar container in the same pod, sharing its socket
# over a mounted emptyDir at /var/run/tailscale.
ARG TAILSCALE_VERSION=1.102.4
ARG TARGETARCH
RUN apt-get update && apt-get install -y --no-install-recommends jq ca-certificates \
    && rm -rf /var/lib/apt/lists/* \
    && curl -fsSL "https://pkgs.tailscale.com/stable/tailscale_${TAILSCALE_VERSION}_${TARGETARCH}.tgz" \
      | tar -xz --strip-components=1 -C /usr/local/bin "tailscale_${TAILSCALE_VERSION}_${TARGETARCH}/tailscale" \
    && rm -f /usr/bin/pebble

COPY pam-tailscale-whois.sh /usr/local/bin/pam-tailscale-whois.sh
RUN chmod 0755 /usr/local/bin/pam-tailscale-whois.sh

COPY pam-sshd /etc/pam.d/sshd
COPY sshd-tailscale.conf /etc/ssh/sshd_config.d/10-tailscale-whois.conf

LABEL org.opencontainers.image.source="https://github.com/HomeScaleCloud/homescale" \
      org.opencontainers.image.description="Slinky Slurm login node with Tailscale-identity SSH (no keys, no static user list)"
