# HomeScale

!!! warning "These docs are new and still finding their feet"
    This documentation was recently bootstrapped and is largely AI-generated from the repository. As a result, some pages may be incomplete, imprecise, or lag behind recent changes. Over time, the docs will be reviewed, corrected, and expanded until they become a reliable reference. For now, treat the repository itself as the source of truth.

HomeScale is a GitOps monorepo for private Kubernetes clusters. ArgoCD watches this repo and reconciles all cluster state automatically on merge to `main`.

## Common tasks

- [Deploying an app](operations/deploying-an-app.md) — add a new app to the catalog
- [App reference](operations/apps.md) — full `app.yaml` field reference
- [Cluster operations](operations/clusters.md) — adding clusters, bootstrapping, upgrades
- [Backups](operations/backups.md) — VolSync backup and restore
- [Runbooks](runbooks/index.md) — alert runbooks

## Architecture

- [Overview](architecture/overview.md) — GitOps flow, app catalog, CI/CD pipeline
- [Networking](architecture/networking.md) — NetBird mesh, internal and external service exposure
- [Secrets](architecture/secrets.md) — Infisical, InfisicalSecret CRs, adding secrets
