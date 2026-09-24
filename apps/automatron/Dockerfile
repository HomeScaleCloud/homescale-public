FROM python:3.12-slim

RUN apt-get update && apt-get install -y --no-install-recommends \
        curl ca-certificates jq openssh-client gettext-base \
    && rm -rf /var/lib/apt/lists/*

# kubectl
RUN curl -fsSL -o /usr/local/bin/kubectl \
        "https://dl.k8s.io/release/$(curl -fsSL https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl" \
    && chmod +x /usr/local/bin/kubectl

# helm
RUN curl -fsSL https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash

# omnictl (public GitHub release — no Tailscale reachable at build time)
RUN curl -fsSL -o /usr/local/bin/omnictl \
        "https://github.com/siderolabs/omni/releases/latest/download/omnictl-linux-amd64" \
    && chmod +x /usr/local/bin/omnictl

# yq
RUN curl -fsSL -o /usr/local/bin/yq \
        "https://github.com/mikefarah/yq/releases/latest/download/yq_linux_amd64" \
    && chmod +x /usr/local/bin/yq

RUN pip install --no-cache-dir ansible-core kubernetes infisicalsdk==1.0.17

COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

ENTRYPOINT ["/entrypoint.sh"]
