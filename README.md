# ![HomeScale](https://raw.githubusercontent.com/HomeScaleCloud/homescale/refs/heads/main/media/homescale-banner.png)

### Enterprise-grade infrastructure, built for homelab
![ci](https://github.com/HomeScaleCloud/homescale/actions/workflows/ci.yaml/badge.svg?branch=main)

This monorepo contains the Infrastructure as Code (IaC) used to manage **HomeScale**, a collection of private cloud environments for myself, friends, and family.

## 🔧 Key Technologies

### **Infrastructure**
- [Talos Linux](https://www.talos.dev/) - API-managed OS for running k8s
- [Omni](https://omni.siderolabs.com/) - Centralized machine & cluster management for Talos
- [Kubernetes (k8s)](https://kubernetes.io/) - Workload/container orchestration
- [rook-ceph](https://rook.io/) - Distributed storage for Kubernetes

### **Networking & Security**
- [Tailscale](https://tailscale.com/) - Cloud-based P2P WireGuard VPN
- [Teleport](https://goteleport.com/) - Secure access proxy
- [1Password Operator](https://developer.1password.com/docs/k8s/k8s-operator/) - Kubernetes secrets management

### **GitOps & Automation**
- [GitHub Actions](https://github.com/features/actions) - CI/CD
- [OpenTofu](https://opentofu.org/) - Infrastructure as Code (IaC)
- [ArgoCD](https://argo-cd.readthedocs.io/en/stable/) - GitOps for Kubernetes
