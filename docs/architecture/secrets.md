# Secrets Management

[Infisical](https://infisical.com/) is the central secrets store for HomeScale. Secrets are stored in Infisical projects, and the [Infisical Kubernetes operator](https://infisical.com/docs/integrations/platforms/kubernetes) (deployed as the `infisical` app at syncWave -35) syncs them into cluster namespaces via `InfisicalSecret` custom resources.

**No secrets belong in this Git repo.** The [`detect-secrets`](https://github.com/Yelp/detect-secrets) pre-commit hook scans every commit and blocks any file that looks like it contains credentials. Use `# pragma: allowlist secret` to suppress false positives on non-secret strings (e.g. a field named `secretName`).

## How it works

```
Infisical project
  └─ /k8s/<purpose>/<cluster>/<app>/   ← path containing key-value pairs
       ▲
       │  synced by Infisical operator
       │
InfisicalSecret CR (in app namespace)
       │
       ▼
Kubernetes Secret (in app namespace, used by pods)
```

The Infisical operator watches `InfisicalSecret` CRs and keeps the corresponding Kubernetes `Secret` up to date. When a secret value changes in Infisical, the operator syncs the new value automatically — no redeploy needed.

## Secret path convention

Secrets in Infisical follow a consistent path structure:

```
/k8s/<purpose>/<cluster-name>/<app>
```

| Segment | Example | Notes |
|---------|---------|-------|
| `/k8s/` | — | Prefix for all secrets synced to Kubernetes |
| `<purpose>` | `volsync`, `app` | Logical category |
| `<cluster-name>` | `<region>-prod`, `mgmt` | Cluster the secret is used on |
| `<app>` | `home-assistant` | App or component name |

Examples:
- `/k8s/volsync/<cluster>/home-assistant` — VolSync restic credentials for the home-assistant app on a given cluster
- `/k8s/app/mgmt/argocd` — ArgoCD-specific credentials on the management cluster

## InfisicalSecret CR

Each app that needs secrets includes a `templates/secret.yaml` in its Helm chart:

```yaml
apiVersion: secrets.infisical.com/v1alpha1
kind: InfisicalSecret
metadata:
  name: my-app
  namespace: my-app
spec:
  hostAPI: https://app.infisical.com/api
  resyncInterval: 60  # seconds
  authentication:
    universalAuth:
      secretsScope:
        projectSlug: homescale
        envSlug: prod
        secretsPath: /k8s/app/{{ .Values.cluster.name }}/my-app
      credentialsRef:
        secretName: infisical-universal-auth
        secretNamespace: infisical
  managedSecretReference:
    secretName: my-app-secrets
    secretNamespace: my-app
```

The `credentialsRef` points at a bootstrap secret (`infisical-universal-auth`) that is created manually once per cluster during initial setup. All other secrets flow from there.

See the [Infisical Kubernetes operator docs](https://infisical.com/docs/integrations/platforms/kubernetes) for full CR reference.

## Adding a secret to an app

1. **Add the key/value in Infisical** at the appropriate path (`/k8s/<purpose>/<cluster>/<app>`).
2. **Reference it in the app's `InfisicalSecret` CR** — if the CR already has the right `secretsPath`, the value is automatically included in the managed Kubernetes Secret.
3. **Reference the Kubernetes Secret in your pod spec** — via `env.valueFrom.secretKeyRef` or `envFrom.secretRef` as usual.

If the app doesn't have an `InfisicalSecret` CR yet, add `templates/secret.yaml` to the app's Helm chart following the pattern above.

## VolSync secrets

VolSync restic credentials are a special case. Each app that uses VolSync needs a secret at:

```
/k8s/volsync/<cluster-name>/<app>
```

containing:

| Key | Value |
|-----|-------|
| `RESTIC_REPOSITORY` | Restic repo URL (e.g. `s3:https://…/bucket/app`) |
| `RESTIC_PASSWORD` | Restic encryption passphrase |
| `AWS_ACCESS_KEY_ID` | S3 access key (if using S3-compatible storage) |
| `AWS_SECRET_ACCESS_KEY` | S3 secret key |

The `volsync.yaml` template in the app's Helm chart creates the `InfisicalSecret` CR that syncs this into a Secret named `<app>-volsync-repo`.
