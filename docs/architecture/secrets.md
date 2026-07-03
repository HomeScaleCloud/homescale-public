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

Most apps' secrets live at a simple per-app path, with an optional subpath for a specific secret within that app:

```
/k8s/<app>[/<subpath>]
```

Examples (all real, from `apps/*/templates/secret.yaml`):
- `/k8s/omni` — the omni app's secrets
- `/k8s/argocd` — ArgoCD's SAML and notifications secrets
- `/k8s/argocd/deploy-key` — ArgoCD's Git deploy key, split out as its own path
- `/k8s/metrics/grafana`, `/k8s/metrics/alertmanager` — per-component secrets under the `metrics` app

VolSync is the one exception: every app's restic credentials are read from a single shared path, `/k8s/volsync` (not a per-app or per-cluster path) — see [VolSync secrets](#volsync-secrets) below.

## InfisicalSecret CR

Each app that needs secrets includes a `templates/secret.yaml` in its Helm chart:

```yaml
apiVersion: secrets.infisical.com/v1alpha1
kind: InfisicalSecret
metadata:
  name: k8s-my-app
  namespace: my-app
spec:
  syncConfig:
    resyncInterval: 60s
  authentication:
    universalAuth:
      secretsScope:
        projectSlug: "homescale"
        envSlug: "prod"
        secretsPath: "/k8s/my-app"
      credentialsRef:
        secretName: infisical-operator-auth
        secretNamespace: infisical
  managedKubeSecretReferences:
    - secretName: my-app-secrets
      secretNamespace: my-app
      creationPolicy: Owner
      secretType: Opaque
```

`managedKubeSecretReferences` is a list — an app can sync multiple Kubernetes Secrets from different Infisical subpaths in one CR (see `apps/argocd/templates/secret.yaml` for an app with two). The `credentialsRef` points at `infisical-operator-auth`, a bootstrap secret created manually once per cluster during initial setup. All other secrets flow from there.

See the [Infisical Kubernetes operator docs](https://infisical.com/docs/integrations/platforms/kubernetes) for full CR reference.

## Adding a secret to an app

1. **Add the key/value in Infisical** at the appropriate path (`/k8s/<purpose>/<cluster>/<app>`).
2. **Reference it in the app's `InfisicalSecret` CR** — if the CR already has the right `secretsPath`, the value is automatically included in the managed Kubernetes Secret.
3. **Reference the Kubernetes Secret in your pod spec** — via `env.valueFrom.secretKeyRef` or `envFrom.secretRef` as usual.

If the app doesn't have an `InfisicalSecret` CR yet, add `templates/secret.yaml` to the app's Helm chart following the pattern above.

## VolSync secrets

VolSync restic credentials are a special case: every app reads from the same shared Infisical path, `/k8s/volsync`, rather than a per-app path:

```
/k8s/volsync
```

containing:

| Key | Value |
|-----|-------|
| `RESTIC_REPOSITORY` | Base restic repo URL (e.g. `s3:https://…/bucket`), *without* a per-app suffix |
| `RESTIC_PASSWORD` | Restic encryption passphrase, shared across all apps |
| `AWS_ACCESS_KEY_ID` | S3 access key (if using S3-compatible storage) |
| `AWS_SECRET_ACCESS_KEY` | S3 secret key |

The app's `volsync.yaml` template creates an `InfisicalSecret` CR that pulls `includeAllSecrets: true` from `/k8s/volsync`, then overrides just `RESTIC_REPOSITORY` in its `template.data` to append `/<cluster>/<app>` at render time — so the actual per-app repository path is computed in the Helm template, not stored in Infisical:

```yaml
managedKubeSecretReferences:
  - secretName: my-app-volsync-repo
    secretNamespace: my-app
    creationPolicy: Owner
    secretType: Opaque
    template:
      includeAllSecrets: true
      data:
        RESTIC_REPOSITORY: "{{ .RESTIC_REPOSITORY.Value }}/{{ .Values.cluster.name }}/my-app"
```

See `apps/home-assistant/templates/secret.yaml` or `apps/omni/templates/secret.yaml` for real examples. The resulting Secret is named `<app>-volsync-repo`.

!!! note "Terraform also provisions a per-app Infisical folder that goes unused"
    `infra/terraform/volsync.tf` creates a folder at `/k8s/volsync/<cluster>/<app>/` with reference-expression secrets deriving from the shared base. No shipped app's `InfisicalSecret` CR actually points at that path today — they all read `/k8s/volsync` directly and do their own suffixing as shown above. Worth knowing if you're investigating why that per-app folder looks empty or unreferenced.
