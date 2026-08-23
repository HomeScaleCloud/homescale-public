FROM ghcr.io/actions/actions-runner:latest

USER root

RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        gnupg \
        lsb-release \
        unzip \
        python3-pip \
        python-is-python3 \
    && rm -rf /var/lib/apt/lists/*

# HashiCorp apt repo (terraform)
RUN curl -fsSL https://apt.releases.hashicorp.com/gpg | gpg --dearmor -o /usr/share/keyrings/hashicorp-archive-keyring.gpg \
    && echo "deb [signed-by=/usr/share/keyrings/hashicorp-archive-keyring.gpg] https://apt.releases.hashicorp.com $(lsb_release -cs) main" \
        > /etc/apt/sources.list.d/hashicorp.list \
    && apt-get update \
    && apt-get install -y --no-install-recommends terraform \
    && rm -rf /var/lib/apt/lists/*

# GitHub CLI apt repo
RUN curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg -o /usr/share/keyrings/githubcli-archive-keyring.gpg \
    && echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" \
        > /etc/apt/sources.list.d/github-cli.list \
    && apt-get update \
    && apt-get install -y --no-install-recommends gh \
    && rm -rf /var/lib/apt/lists/*

# Tailscale
RUN curl -fsSL https://tailscale.com/install.sh | sh

# Helm
RUN curl -fsSL https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash

# kubectl
RUN curl -fsSL -o /usr/local/bin/kubectl \
        "https://dl.k8s.io/release/$(curl -fsSL https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl" \
    && chmod +x /usr/local/bin/kubectl

# yq
RUN curl -fsSL -o /usr/local/bin/yq \
        "https://github.com/mikefarah/yq/releases/latest/download/yq_linux_amd64" \
    && chmod +x /usr/local/bin/yq

# uv
ENV UV_INSTALL_DIR=/usr/local/bin
RUN curl -fsSL https://astral.sh/uv/install.sh | sh

# Python tooling used across CI jobs (pre-commit, deploy.yaml's ansible job, docs build, mirror.yaml)
RUN pip3 install --break-system-packages --no-cache-dir \
        pre-commit \
        ansible \
        kubernetes \
        infisicalsdk==1.0.17 \
        mkdocs-material \
        git-filter-repo

# requirements.yml here is a build-time copy of infra/ansible/requirements.yml (synced in by
# build.yaml before building, since Docker can't COPY from outside its own build context) --
# nothing to keep in sync manually. For a local build: cp ../../infra/ansible/requirements.yml
# apps/github-runner/ first, then `docker build apps/github-runner -t github-runner`.
COPY requirements.yml /tmp/ansible-requirements.yml
RUN ansible-galaxy collection install \
        -r /tmp/ansible-requirements.yml \
        -p /usr/share/ansible/collections \
    && rm /tmp/ansible-requirements.yml

USER runner
