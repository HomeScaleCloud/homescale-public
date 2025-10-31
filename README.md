# ![HomeScale](https://raw.githubusercontent.com/HomeScaleCloud/homescale-public/refs/heads/main/media/homescale-banner.png)

### Enterprise-grade infrastructure, built for homelab
![ci](https://github.com/HomeScaleCloud/homescale/actions/workflows/ci.yaml/badge.svg?branch=main)

This monorepo contains the Infrastructure as Code (IaC) used to manage **HomeScale**, a collection of private cloud environments for myself, friends, and family.

## 🔧 Key Technologies

### **Infrastructure**
- [Kubernetes (k8s)](https://kubernetes.io/) - Workload/container orchestration
- [Talos Linux](https://www.talos.dev) - API-driven OS designed for Kubernetes

### **Networking & Security**
- [Entra ID](https://www.microsoft.com/en-us/security/business/identity-access/microsoft-entra-id) - Identity and privilege management
- [Tailscale](https://tailscale.com) - Peer-to-peer zero-trust networking
- [1Password (Operator)](https://developer.1password.com/docs/k8s/k8s-operator/) - Kubernetes secrets management

### **GitOps & Automation**
- [GitHub Actions](https://github.com/features/actions) - CI/Jobs runner
- [Terraform](https://developer.hashicorp.com/terraform) - Infrastructure as Code (IaC)
- [ArgoCD](https://argo-cd.readthedocs.io/en/stable/) - GitOps for Kubernetes
