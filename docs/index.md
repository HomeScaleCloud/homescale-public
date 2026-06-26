# HomeScale

HomeScale is a GitOps monorepo for private Kubernetes clusters. ArgoCD watches this repo and reconciles all cluster state automatically on merge to `main`.

## Common tasks

- [Deploying an app](operations/deploying-an-app.md) — add a new app to the catalog
- [App reference](architecture/apps.md) — full `app.yaml` field reference
- [Clusters](architecture/clusters.md) — adding clusters, bootstrapping, upgrades
- [Backups](architecture/backups.md) — VolSync backup and restore
- [Runbooks](runbooks/index.md) — alert runbooks

## Architecture

- [Overview](architecture/overview.md) — GitOps flow, app catalog, CI/CD pipeline
- [Networking](architecture/networking.md) — NetBird mesh, internal and external service exposure
- [Secrets](architecture/secrets.md) — Infisical, InfisicalSecret CRs, adding secrets
