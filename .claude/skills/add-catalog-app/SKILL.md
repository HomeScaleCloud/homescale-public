---
name: add-catalog-app
description: Use when adding a new app to the HomeScale app catalog (a new apps/<name>/ directory), enabling an existing app on a new cluster, or changing how an app is exposed/secured (Tailscale ACL, public exposure, secrets). Walks the full onboarding sequence in the order it actually needs to happen and calls out the steps that fail silently or get admission-rejected instead of erroring at commit time.
---

# Add a catalog app

Full reference for the per-app file layout lives in `docs/architecture/apps.md` — read it for anything not covered here. This skill is the *ordered checklist and gotchas*, not a field dictionary.

## 1. Scaffold the directory

```
apps/<name>/
  Chart.yaml          # required — catalog/ArgoCD wiring lives in its annotations:
  values.yaml          # optional — Helm input values for this chart
  tailscale.yaml        # optional — Tailscale ACL policy (Terraform-only, see step 4)
  cloudflare.yaml        # optional — public exposure (Terraform-only, see step 6)
  templates/
    deployment.yaml / service.yaml   # if hand-written
    secret.yaml                       # if it needs Infisical secrets
    volsync.yaml                      # if its PVCs need backups
```

If wrapping an upstream chart, `templates/` holds only pass-through resources (`InfisicalSecret`, `volsync.yaml`, etc.) and `Chart.yaml` pulls the upstream chart as a `dependencies:` entry. If hand-writing templates, omit `dependencies`.

## 2. Write `Chart.yaml` annotations

Minimum (alongside the normal `apiVersion`/`name`/`description`/`version` fields):

```yaml
annotations:
  REDACTED/namespace: <name>
  REDACTED/default-deploy: "false"      # don't accidentally deploy everywhere
```

Only set `REDACTED/default-deploy: "true"` when you actually want it; the catalog defaults to `false` if the annotation is omitted entirely, but set it explicitly so the intent is visible in the diff. Other optional annotations: `REDACTED/sync-wave` (default `"0"`), `REDACTED/pod-security`, `REDACTED/sync-options` (comma-separated), and — rare, only for apps needing ArgoCD drift-suppression or a multi-source chart — `REDACTED/ignore-differences`/`REDACTED/extra-sources`:

```yaml
annotations:
  REDACTED/ignore-differences: |
    - group: admissionregistration.k8s.io
      kind: MutatingWebhookConfiguration
      name: my-webhook
      jsonPointers:
        - /webhooks
```

The value is a YAML block scalar (`|`) — still a plain string as far as `Chart.yaml`'s `annotations: map[string]string` is concerned, but the catalog chart parses its *content* back into a real list with `fromYamlArray`. See `apps/metrics/Chart.yaml` (`ignore-differences`) or `apps/slurm/Chart.yaml` (`extra-sources`) for real examples.

## 3. Enable it per cluster

Do **not** set `deploy: true` in `Chart.yaml` itself. Enable in `clusters/<cluster>/apps.yaml`, under `spec.sources[1].helm.values.apps.<name>`:

```yaml
apps:
  <name>:
    deploy: true
```

This override object is deep-merged onto the app's assembled base config (`Chart.yaml` annotations + `values.yaml`, combined by the catalog chart), so any top-level key (`values`, `syncWave`, `podSecurity`, `ignoreDifferences`, ...) can be overridden per cluster — not just `deploy`. It does **not** reach `tailscale.yaml`/`cloudflare.yaml` — those are Terraform-only inputs, not part of the Helm catalog's merge at all, so they can't be overridden per cluster this way.

**Gotcha:** the merge is deep on maps but **lists are replaced wholesale, not concatenated.** Overriding `values.someList` at the cluster level replaces the base list entirely — if the base already had entries you want to keep, repeat them in the override.

## 4. Access control — Tailscale ACL (required)

Add `apps/<name>/tailscale.yaml`. **Access is denied by default with no `tailscale.yaml`** — this is the most common way a newly-added app is unreachable after merge with no error anywhere.

```yaml
policy:
  rules:
    - sources: ["group:owners@REDACTED"]
      protocol: tcp
      ports: ["443"]
```

`sources` are literal ACL identifiers, spelled out in full (no short-alias remapping): `group:<name>@REDACTED`, `tag:github-actions`, `tag:app-<other-app>`, or `*`.

This file is **not a Helm value** — Terraform (`infra/terraform/modules/tailscale/acl.tf`) reads every `apps/*/tailscale.yaml` directly via `fileset`/`yamldecode` and flattens all apps' rules into one `tailscale_acl` resource. It has no effect on `helm template` output, which makes it look like dead config — it is not. Never delete it as unused.

## 5. Internal exposure (tailnet Service)

If the app exposes a `Service`, opt into tailnet routing:

```yaml
spec:
  type: LoadBalancer
  loadBalancerClass: tailscale
```

and set **all four** of these annotations — a Kyverno `ValidatingPolicy` (`apps/kyverno/templates/policy-tailscale-service-annotations.yaml`) rejects the Service at admission time if any are missing or malformed, so this fails at `kubectl apply`/ArgoCD sync, not at review time:

```yaml
metadata:
  annotations:
    tailscale.com/tags: "tag:k8s,tag:app-<name>,tag:env-{{ .Values.env.name }}"
    tailscale.com/hostname: "<name>-{{ .Values.env.name }}"
    tailscale.com/proxy-group: ingress
    external-dns.kubernetes.io/hostname: "<name>.{{ .Values.env.name }}REDACTED"
```

The policy specifically requires: `tailscale.com/tags` containing both `tag:k8s` and a `tag:app-*`/`tag:k8s-api`/`tag:omni-k8s` entry and `tag:env-<env.name>`, and `external-dns.kubernetes.io/hostname` ending in `REDACTED`.

## 6. External exposure (optional, public internet)

Add `apps/<name>/cloudflare.yaml` (its `expose:` key is a list — one app can expose multiple Services/ports/fqdns). **`service:` is required on every entry** — there's no fallback to `releaseName`/directory name:

```yaml
expose:
  - env: production          # which cluster's Cloudflare tunnel to route through
    fqdn: myapp.example.com   # must be in a Cloudflare zone in the HomeScale account
    port: 80
    service: <name>            # the Kubernetes Service name to route to
```

To gate it behind Entra ID login at Cloudflare's edge, add `access:`:

```yaml
- env: production
  fqdn: myapp.example.com
  port: 80
  service: <name>
  access:
    allowedIdps: []        # omit to allow any configured IdP
    sessionDuration: "24h" # optional
```

Note: this currently only supports "allow any authenticated user" — there's no group/email restriction in the Terraform module (`infra/terraform/modules/cloudflare/access.tf`) today. Flag this limitation if the user asks for group-scoped access.

Like `tailscale.yaml`, this file is **not a Helm value** — Terraform (`infra/terraform/modules/cloudflare/main.tf`) reads every `apps/*/cloudflare.yaml` directly. The one exception: the catalog chart also reads each entry's `fqdn` (from this same file) to populate `.Values.homescale.exposePublicFqdns` for charts that need their own public hostname (e.g. a Knative `DomainMapping`, or a `Certificate`'s `dnsNames` when an entry sets `tls: true`).

## 7. Secrets (if needed)

1. Add the key/value in Infisical at `/k8s/<name>[/<subpath>]`.
2. Add `templates/secret.yaml`:

```yaml
apiVersion: secrets.infisical.com/v1alpha1
kind: InfisicalSecret
metadata:
  name: k8s-<name>
  namespace: <name>
spec:
  syncConfig:
    resyncInterval: 60s
  authentication:
    universalAuth:
      secretsScope:
        projectSlug: "homescale"
        envSlug: "prod"
        secretsPath: "/k8s/<name>"
      credentialsRef:
        secretName: infisical-operator-auth
        secretNamespace: infisical
  managedKubeSecretReferences:
    - secretName: <name>-secrets
      secretNamespace: <name>
      creationPolicy: Owner
      secretType: Opaque
```

3. Reference the resulting Kubernetes Secret in the pod spec via `secretKeyRef`/`secretRef`.

## 8. VolSync backups (if it has persistent state worth backing up)

Add `templates/volsync.yaml` (two-mode template gated by `.Values.volsync.restore.enabled`) and a matching `templates/secret.yaml` entry pulling from the shared `/k8s/volsync` Infisical path — copy the pattern from `apps/home-assistant/templates/volsync.yaml` and `templates/secret.yaml`. That app is multi-PVC (a `$pvcs := list "..." "..."` at the top of the template); for a single-PVC app, use the same pattern with a one-element list. See the `volsync-restore` skill for the restore procedure once this is wired up.

## 9. First-party Docker image (if needed)

Put the `Dockerfile` at `apps/<name>/Dockerfile` or `apps/<name>/src/Dockerfile` (both patterns exist — `build.yaml`'s discovery step handles either). CI builds and pushes `ghcr.io/homescalecloud/<name>:<git-sha>` and `:latest` on every merge to `main`. Pin to the SHA tag in `values.yaml`, not `latest`, for anything beyond scratch/dev apps:

```yaml
image:
  repository: ghcr.io/homescalecloud/<name>
  tag: "abc1234"  # pragma: allowlist secret
```

The `# pragma: allowlist secret` comment is required to suppress a `detect-secrets` false positive on the word after `tag:`.

## 10. Alerts (if the app ships a `PrometheusRule`)

Every alert needs, in the same change: a runbook at `docs/runbooks/<alert-name-kebab-case>.md`, a nav entry in `mkdocs.yml` under the right group, and a `runbook_url: "https://REDACTED/runbooks/<alert-name-kebab-case>/"` annotation on the alert. Match the existing runbook format (severity/alert/dashboard header, "What this means," "Common causes" table — no "Diagnosis" section).

## 11. Validate locally before opening the PR

```bash
helm template <name> apps/<name>/
helm template apps -f apps/values.yaml --set env.name=<cluster>
yamllint -c .yamllint.yaml apps/<name>/
```

## 12. Commit and PR

Conventional Commits, enforced by gitlint/CI: `feat(<name>): add <name> to the app catalog`. On the PR, CI lints the chart, builds any Docker image, and runs `terraform plan` (previewing the Tailscale ACL / Cloudflare changes from steps 4–6). On merge, `terraform apply` runs and ArgoCD picks up the new `Application` within ~30s.
