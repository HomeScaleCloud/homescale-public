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
    unzip \
    && rm -rf /var/lib/apt/lists/*

# renovate: datasource=hashicorp depName=terraform
ARG TERRAFORM_VERSION=1.15.5
RUN curl -fsSL "https://releases.hashicorp.com/terraform/${TERRAFORM_VERSION}/terraform_${TERRAFORM_VERSION}_linux_amd64.zip" \
    -o /tmp/terraform.zip \
    && unzip /tmp/terraform.zip -d /usr/local/bin terraform \
    && rm /tmp/terraform.zip

# renovate: datasource=github-releases depName=netbirdio/netbird extractVersion=^v(?<version>.+)$
ARG NETBIRD_VERSION=0.72.2
RUN curl -fsSL "https://github.com/netbirdio/netbird/releases/download/v${NETBIRD_VERSION}/netbird_${NETBIRD_VERSION}_linux_amd64.deb" \
    -o /tmp/netbird.deb \
    && dpkg -i /tmp/netbird.deb \
    && rm /tmp/netbird.deb \
    && rm -rf /var/lib/apt/lists/* /var/lib/netbird/

# renovate: datasource=pypi depName=ansible
ARG ANSIBLE_VERSION=14.0.0
RUN pip3 install --no-cache-dir --break-system-packages "ansible==${ANSIBLE_VERSION}"

RUN curl -fsSLk -o /usr/local/bin/omnictl \
    https://REDACTED/omnictl/omnictl-linux-amd64 \
    && chmod +x /usr/local/bin/omnictl

LABEL org.opencontainers.image.source="https://github.com/HomeScaleCloud/homescale" \
      org.opencontainers.image.description="GitHub Actions runner image for homescale"
