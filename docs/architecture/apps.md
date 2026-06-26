# Apps

Each app lives in `apps/<name>/` and is controlled by an `app.yaml`. The app catalog Helm chart (`apps/`) reads every `apps/*/app.yaml` and generates one ArgoCD `Application` per enabled app per cluster.

Apps with both a `Chart.yaml` and a `Dockerfile` under `apps/<name>/` are built and pushed to `ghcr.io/homescalecloud/<name>` by CI on every merge to `main`.

---

## `app.yaml` field reference

### Required fields

| Field | Type | Description |
|-------|------|-------------|
| `path` | string | Path to the Helm chart directory (e.g. `apps/my-app`) |
| `namespace` | string | Kubernetes namespace the app deploys into |

---

### Deployment control

These fields decide which clusters the app lands on.

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `defaultDeploy` | bool | `false` | Deploy to every cluster unless overridden |
| `clusters.<name>.deploy` | bool | — | Per-cluster override of `defaultDeploy`. Set `true` to enable on a cluster where `defaultDeploy: false`, or `false` to skip a cluster where `defaultDeploy: true` |
| `clusters.<name>.*` | any | — | Any other field placed under a cluster key is deep-merged over the base `app.yaml` for that cluster only (values, syncWave, etc.) |

**Example — deploy only to `boa1-prod`, with a cluster-specific value override:**
```yaml
defaultDeploy: false
clusters:
  boa1-prod:
    deploy: true
    values:
      someKey: clusterSpecificValue
```

---

### Helm / ArgoCD source config

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `releaseName` | string | app directory name | Helm release name |
| `repoURL` | string | global `repoURL` | Git repo URL; override to point at an external chart repo |
| `targetRevision` | string | global `targetRevision` (`main`) | Git ref (branch, tag, or SHA) |
| `values` | object | `{}` | Helm values passed to the chart. Supports Go template expressions `{{ .Values.cluster.name }}` and `{{ .Values.cluster.region }}` |
| `valueFiles` | list of strings | — | Additional Helm value files to load (paths relative to the chart) |
| `extraSources` | list of ArgoCD sources | — | Adds extra source entries to the ArgoCD Application, switching it to multi-source mode. The app's own chart is always the first source |

**Example — `extraSources` for a chart that needs a second repo:**
```yaml
extraSources:
  - repoURL: https://charts.example.com
    chart: some-chart
    targetRevision: 1.2.3
```

---

### Sync behavior

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `syncWave` | int | `0` | ArgoCD sync wave. Lower numbers sync first. See [sync wave order](#sync-wave-order) below |
| `syncPolicy` | object | global automated prune+self-heal | Merged over the global `syncPolicy`. Use to disable automated sync or self-heal for a specific app |
| `syncOptions` | list of strings | `["CreateNamespace=true"]` | Concatenated with the global `syncOptions` (duplicates removed). Common values: `ServerSideApply=true` |
| `ignoreDifferences` | list | — | ArgoCD `ignoreDifferences` entries — suppress spurious drift detection on fields that are mutated out-of-band (e.g. webhook CABundles, generated secrets) |
| `annotations` | object | — | Extra annotations added to the ArgoCD `Application` resource itself (not to app workloads) |

**Example — ignore a webhook CA bundle that gets rewritten by cert-manager:**
```yaml
ignoreDifferences:
  - group: admissionregistration.k8s.io
    kind: MutatingWebhookConfiguration
    name: my-webhook
    jsonPointers:
      - /webhooks
```

**Example — disable automated sync for a specific app:**
```yaml
syncPolicy:
  automated: null
```

---

### Namespace config

| Field | Type | Description |
|-------|------|-------------|
| `podSecurity` | string | Applies Kubernetes [Pod Security Standards](https://kubernetes.io/docs/concepts/security/pod-security-standards/) labels to the namespace. Valid values: `privileged`, `baseline`, `restricted` |

When set, the namespace gets `pod-security.kubernetes.io/enforce`, `/warn`, and `/audit` labels all set to the chosen level.

---

### ArgoCD destination override

By default, apps deploy to the cluster that is running ArgoCD (determined by cluster name). These fields are rarely needed.

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `destination.server` | string | `https://kubernetes.default.svc` | Override the destination API server URL |
| `destination.name` | string | current cluster name | Override the destination cluster name |
| `project` | string | `default` | ArgoCD project to assign this app to |

---

### NetBird access policy (`netbird:`)

Defines who can reach this app across the NetBird mesh. If absent, access is **denied by default**.

```yaml
netbird:
  policy:
    rules:
      - sources: ["team-infra-plat", "app:other-app"]
        protocol: tcp
        ports: ["443", "9090"]
      - sources: ["all"]
        protocol: udp
        ports: ["25565"]
```

| Field | Type | Description |
|-------|------|-------------|
| `netbird.policy.rules` | list | One or more access rules. Each rule becomes a separate `netbird_policy` resource named `app-<name>` (single rule) or `app-<name>-0`, `app-<name>-1`, … (multiple rules) |
| `rules[].sources` | list of strings | Source groups that are granted access. See valid values below |
| `rules[].protocol` | string | `tcp` or `udp` |
| `rules[].ports` | list of strings | Port numbers as strings (e.g. `["80", "443"]`) |

The **destination** is always the app's own NetBird group (`app-<name>`), created automatically by Terraform for every app directory.

**Valid `sources` values:**

| Value | Who |
|-------|-----|
| `team-infra-plat` | Infrastructure platform team |
| `team-sec-plat` | Security platform team |
| `github-actions` | CI/CD runners |
| `owners` | Owners group (personal/family access) |
| `sg-k8s-admin` | Kubernetes admins |
| `all` | Everyone on the NetBird mesh |
| `app:<name>` | Another app's NetBird group (colon-separated, e.g. `app:metrics`) |

---

### Public exposure (`exposePublic:`)

!!! warning "Terraform input — not Helm config"
    The `exposePublic:` block is read directly by Terraform (`infra/terraform/modules/cloudflare/`). It creates a Cloudflare tunnel ingress rule and a DNS record. Never delete it thinking it's dead config.

Use this to expose an app to the public internet via a Cloudflare tunnel. Terraform creates a `cloudflare_zero_trust_tunnel_cloudflared_config` ingress entry and a proxied `CNAME` DNS record.

```yaml
exposePublic:
  cluster: boa1-prod   # which cluster's Cloudflare tunnel to route through
  fqdn: myapp.io       # public hostname (must be in a Cloudflare zone Terraform manages)
  port: 80             # backend service port
```

| Field | Type | Description |
|-------|------|-------------|
| `cluster` | string | The cluster whose Cloudflare tunnel this app is routed through |
| `fqdn` | string | Public fully-qualified domain name. The apex zone must be a Cloudflare-managed zone |
| `port` | int | Port on the Kubernetes Service (`<releaseName>.<namespace>.svc.cluster.local:<port>`) that receives traffic |

---

## Sync wave order

| Wave | What syncs |
|------|-----------|
| -40 | cilium |
| -35 | infisical, multus |
| -30 | cert-manager, argocd, rbac |
| -25 | generic-device-plugin-tun |
| -20 | netbird, cert-manager-crs, spegel |
| -10 | external-dns, netbird-crs, kubelet-serving-cert-approver |
| -5 | volsync |
| 0 | all other apps (default) |
| 1+ | apps that must come after the default wave |

---

## Full example

```yaml
path: apps/my-app
namespace: my-app
releaseName: my-app            # optional, defaults to directory name
syncWave: 0
podSecurity: restricted
defaultDeploy: false

syncOptions:
  - ServerSideApply=true

ignoreDifferences:
  - group: admissionregistration.k8s.io
    kind: MutatingWebhookConfiguration
    name: my-app-webhook
    jsonPointers:
      - /webhooks

netbird:
  policy:
    rules:
      - sources: ["team-infra-plat"]
        protocol: tcp
        ports: ["443"]

exposePublic:
  cluster: boa1-prod
  fqdn: myapp.example.com
  port: 80

values:
  cluster:
    name: "{{ .Values.cluster.name }}"
  image:
    tag: "1.2.3"

clusters:
  boa1-prod:
    deploy: true
    values:
      replicaCount: 3
  mgmt:
    deploy: false
```

---

## Linting

```bash
# Render a specific app chart
helm template apps/<app-name> apps/<app-name>/

# Render the full app catalog for a cluster
helm template apps -f apps/values.yaml --set cluster.name=mgmt
```
