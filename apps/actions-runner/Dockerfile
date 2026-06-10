FROM ubuntu:24.04

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update && apt-get install -y --no-install-recommends \
    ca-certificates \
    curl \
    gettext-base \
    git \
    gpg \
    jq \
    python3-pip \
    && rm -rf /var/lib/apt/lists/*

RUN curl -fsSL https://apt.releases.hashicorp.com/gpg \
    | gpg --dearmor -o /usr/share/keyrings/hashicorp-archive-keyring.gpg \
    && echo "deb [arch=amd64 signed-by=/usr/share/keyrings/hashicorp-archive-keyring.gpg] https://apt.releases.hashicorp.com noble main" \
    > /etc/apt/sources.list.d/hashicorp.list \
    && apt-get update && apt-get install -y --no-install-recommends terraform \
    && rm -rf /var/lib/apt/lists/*

RUN curl -fsSL https://pkgs.netbird.io/install.sh | sh \
    && rm -rf /var/lib/apt/lists/*

RUN curl -fsSL -o /usr/local/bin/omnictl \
    https://xxx/omnictl/omnictl-linux-amd64 \
    && chmod +x /usr/local/bin/omnictl

LABEL org.opencontainers.image.source="https://github.com/HomeScaleCloud/homescale" \
      org.opencontainers.image.description="GitHub Actions runner image for homescale"
