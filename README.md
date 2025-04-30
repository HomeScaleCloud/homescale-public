# ![HomeScale](https://raw.githubusercontent.com/HomeScaleCloud/homescale/refs/heads/main/media/homescale-banner.png)

### Enterprise-grade infrastructure, built for homelab
![ci](https://github.com/HomeScaleCloud/homescale/actions/workflows/ci.yaml/badge.svg?branch=main)

This monorepo contains the Infrastructure as Code (IaC) used to manage **HomeScale**, a collection of private cloud environments for myself, friends, and family.

## 🔧 Key Technologies

### **Infrastructure**
- [Kubernetes (k8s)](https://kubernetes.io/) - Workload/container orchestration
- [Rancher](https://rancher.com/) - Kubernetes cluster management
- [Harvester](https://harvesterhci.io/) - Cloud-native hypervisor with integration for Rancher

### **Networking & Security**
- [Cloudflare Access](https://www.cloudflare.com/en-gb/zero-trust/products/access/) - Cloud-based zero-trust networking
- [1Password Operator](https://developer.1password.com/docs/k8s/k8s-operator/) - Kubernetes secrets management

### **GitOps & Automation**
- [GitHub Actions](https://github.com/features/actions) - CI/CD
- [Terraform](https://developer.hashicorp.com/terraform) - Infrastructure as Code (IaC)
- [ArgoCD](https://argo-cd.readthedocs.io/en/stable/) - GitOps for Kubernetes
