FROM python:3.14-slim

RUN apt-get update && apt-get install -y --no-install-recommends \
        curl ca-certificates jq openssh-client gettext-base unzip \
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

# terraform (unpinned — matches deploy.yaml's own hashicorp/setup-terraform, which also
# has no terraform_version pinned and so always resolves to latest)
RUN tf_version="$(curl -fsSL https://api.releases.hashicorp.com/v1/releases/terraform/latest | jq -r '.version')" \
    && curl -fsSL -o /tmp/terraform.zip \
        "https://releases.hashicorp.com/terraform/${tf_version}/terraform_${tf_version}_linux_amd64.zip" \
    && unzip -q /tmp/terraform.zip -d /usr/local/bin \
    && rm /tmp/terraform.zip \
    && chmod +x /usr/local/bin/terraform

RUN pip install --no-cache-dir ansible-core kubernetes infisicalsdk==1.0.17

COPY entrypoint.sh /entrypoint.sh
COPY git-key-prep.sh /git-key-prep.sh
RUN chmod +x /entrypoint.sh /git-key-prep.sh

# ansible-galaxy installs collections under $HOME/.ansible at runtime, so this
# needs a real writable home dir, not just a bare non-root UID.
RUN useradd --create-home --uid 1000 --shell /usr/sbin/nologin automatron
USER automatron
ENV HOME=/home/automatron
# Python fully-buffers stdout when it isn't a TTY (as in a container), so without
# this `kubectl logs -f` only sees output in one dump at exit instead of live.
# ANSIBLE_FORCE_COLOR keeps ansible's own OK/CHANGED/FAILED coloring, which it
# otherwise also disables when stdout isn't a TTY.
ENV PYTHONUNBUFFERED=1
ENV ANSIBLE_FORCE_COLOR=1

ENTRYPOINT ["/entrypoint.sh"]
