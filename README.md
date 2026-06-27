# ![HomeScale](https://github.com/HomeScaleCloud/homescale/blob/main/media/homescale-banner.png?raw=true)

![ci](https://github.com/HomeScaleCloud/homescale/actions/workflows/ci.yaml/badge.svg?branch=main)

This monorepo contains the Infrastructure as Code (IaC) used to manage **HomeScale**, a private cloud environment for myself, friends, and family.

## 🔧 Key Technologies

### ☁️ **Infrastructure**
- [Kubernetes (k8s)](https://kubernetes.io/) - Workload/container orchestration
- [Talos Linux](https://www.talos.dev) - Immutable, API-driven OS for k8s
- [Omni](https://omni.siderolabs.com) - Talos lifecycle management
- [Terraform](https://developer.hashicorp.com/terraform) - Cloud infrastructure provisioning

### 🔒 **Networking & Security**
- [Entra ID](https://www.microsoft.com/en-us/security/business/identity-access/microsoft-entra-id) - Identity and access management (SAML/SSO)
- [NetBird](https://netbird.io) - Zero-trust peer-to-peer networking
- [Infisical](https://infisical.com) - Secrets management and k8s sync

### ⚙️ **GitOps & Automation**
- [ArgoCD](https://argo-cd.readthedocs.io/en/stable/) - GitOps continuous delivery for k8s
- [Ansible](https://www.ansible.com) - Configuration management/bootstrapping
- [GitHub Actions](https://github.com/features/actions) - CI/CD
- [Renovate](https://docs.renovatebot.com) - Automated dependency updates

## 📂 Repository Structure

| Directory | Purpose |
|-----------|---------|
| `apps/` | App bundle definitions |
| `clusters/` | Omni cluster definitions and app-of-apps deployments |
| `infra/terraform/` | Cloud and provider resource provisioning |
| `infra/ansible/` | Bootstrapping and configuration/firmware management |
