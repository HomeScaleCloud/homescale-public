# Deploying an App

This page walks through the full process of adding a new application to the HomeScale app catalog.

## How apps work

Every app in the catalog lives at `apps/<name>/`. The `apps/` directory is a Helm chart; `apps/templates/applications.yaml` reads every `apps/*/app.yaml` and renders one [ArgoCD Application](https://argo-cd.readthedocs.io/en/stable/operator-manual/declarative-setup/#applications) per enabled app per cluster.

When you merge a new `app.yaml` to `main`, ArgoCD picks it up in the next reconciliation cycle (within 30 seconds) and deploys it automatically to all clusters where `deploy: true`.

## Quickstart

### 1. Create the app directory

```
apps/
  my-app/
    app.yaml          # required: deployment config
    Chart.yaml        # required: marks this as a Helm chart
    values.yaml       # optional: default values for the chart
    templates/        # Kubernetes resource templates
      deployment.yaml
      service.yaml
      secret.yaml     # if the app needs secrets from Infisical
```

If you're wrapping an upstream Helm chart (not writing your own), the `templates/` directory contains only pass-through resources (like `InfisicalSecret` CRs) and the upstream chart is referenced via a `Chart.yaml` dependency.

### 2. Write `app.yaml`

Start with the minimal required fields:

```yaml
path: apps/my-app
namespace: my-app
defaultDeploy: false      # don't accidentally deploy everywhere

clusters:
  boa1-prod:
    deploy: true
```

Add access control (required — access is denied by default if no `netbird:` block):

```yaml
netbird:
  policy:
    rules:
      - sources: ["owners"]
        protocol: tcp
        ports: ["443"]
```

See the [App reference](apps.md) for the full field list.

### 3. Write `Chart.yaml`

For an app using an upstream chart as a dependency:

```yaml
apiVersion: v2
name: my-app
version: 0.1.0

dependencies:
  - name: my-upstream-chart
    version: "1.2.3"
    repository: https://charts.example.com
```

For a chart with hand-written templates, omit `dependencies`.

### 4. Set up secrets (if needed)

1. Add the secret keys and values to Infisical at `/k8s/app/<cluster-name>/my-app`
2. Add `templates/secret.yaml` to the chart:

```yaml
apiVersion: secrets.infisical.com/v1alpha1
kind: InfisicalSecret
metadata:
  name: my-app
  namespace: my-app
spec:
  hostAPI: https://app.infisical.com/api
  resyncInterval: 60
  authentication:
    universalAuth:
      secretsScope:
        projectSlug: homescale
        envSlug: prod
        secretsPath: /k8s/app/{{ "{{" }} .Values.cluster.name {{ "}}" }}/my-app
      credentialsRef:
        secretName: infisical-universal-auth
        secretNamespace: infisical
  managedSecretReference:
    secretName: my-app-secrets
    secretNamespace: my-app
```

See [Secrets management](../architecture/secrets.md) for full details.

### 5. Validate locally

```bash
# Lint the chart
helm template apps/my-app apps/my-app/

# Render the full catalog including the new app
helm template apps -f apps/values.yaml --set cluster.name=boa1-prod

# YAML lint
yamllint -c .yamllint.yaml apps/my-app/
```

### 6. Open a PR

Commit with a conventional commit message:

```
feat(my-app): add my-app to the app catalog
```

CI will:
- Lint the chart
- Build a Docker image if the directory contains a `Dockerfile`
- Run `terraform plan` (to preview any NetBird/Cloudflare changes from `netbird:` / `exposePublic:`)

On merge to `main`:
- `terraform apply` runs (NetBird policies, DNS records created)
- ArgoCD detects the new `Application` in the next reconciliation and deploys the app

## First-party Docker images

If your app needs a custom image, add a `Dockerfile` to `apps/my-app/`. CI will build and push `ghcr.io/homescalecloud/my-app:latest` on every merge to `main`. Reference it in your `values.yaml`:

```yaml
image:
  repository: ghcr.io/homescalecloud/my-app
  tag: "latest"  # pragma: allowlist secret
```

The `# pragma: allowlist secret` comment suppresses a false positive from `detect-secrets` on the word "latest".

## Exposing the app

### Internal (mesh only)

Access via NetBird is configured with the `netbird:` block in `app.yaml`. Once merged, Terraform creates the policy and the app is reachable at:

```
<service-name>.<namespace>.<cluster>REDACTED
```

for anyone in the specified `sources` groups.

### Public internet

Add an `exposePublic:` block to `app.yaml`:

```yaml
exposePublic:
  cluster: boa1-prod      # which cluster's Cloudflare tunnel to route through
  fqdn: myapp.example.com # must be in a Cloudflare zone Terraform manages
  port: 80                # backend service port
```

Terraform creates the Cloudflare tunnel ingress rule and DNS record on the next apply. See [Networking: external service exposure](../architecture/networking.md#external-service-exposure).

## Cluster-specific overrides

To vary values per cluster, use the `clusters.<name>.values` deep merge:

```yaml
defaultDeploy: false
values:
  replicaCount: 1     # base value

clusters:
  boa1-prod:
    deploy: true
    values:
      replicaCount: 3  # override for prod
```

Any field under `clusters.<name>` is deep-merged over the base `app.yaml` before ArgoCD applies it.

## Enabling backups

If the app has a PVC that needs backup, add a `volsync.yaml` template to the chart and set a backup schedule in `app.yaml`:

```yaml
values:
  volsync:
    backupSchedule: "0 2 * * *"   # daily at 02:00
```

See [Backups](backups.md) for the full procedure.

## Common patterns

### Wrapping an upstream chart

Many apps are thin wrappers around upstream Helm charts. The pattern:

```yaml
# Chart.yaml
dependencies:
  - name: grafana
    version: "8.x.x"
    repository: https://grafana.github.io/helm-charts
```

```yaml
# app.yaml (values section)
values:
  grafana:              # key matches the chart name
    adminPassword: ...
    ingress:
      enabled: false
```

### Using cluster name in values

The `{{ .Values.cluster.name }}` and `{{ .Values.cluster.region }}` Go template expressions are available in `app.yaml` values:

```yaml
values:
  config:
    clusterName: "{{ .Values.cluster.name }}"
    url: "https://myapp.{{ .Values.cluster.name }}REDACTED"
```

These are rendered by the `apps/` chart at sync time.

### Server-side apply

For apps that manage CRDs or large resources, enable [server-side apply](https://kubernetes.io/docs/reference/using-api/server-side-apply/):

```yaml
syncOptions:
  - ServerSideApply=true
```

### Suppressing spurious drift

If a controller mutates a field out-of-band (e.g. cert-manager writing a CA bundle into a webhook), suppress the drift with `ignoreDifferences`:

```yaml
ignoreDifferences:
  - group: admissionregistration.k8s.io
    kind: MutatingWebhookConfiguration
    name: my-app-webhook
    jsonPointers:
      - /webhooks
```
