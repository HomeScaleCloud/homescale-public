# GitHub Actions Self-Hosted Runners

CI can run on a self-hosted runner pool on `boa1-prod` instead of GitHub-hosted `ubuntu-latest` runners, using a custom image (`apps/github-runner/Dockerfile`) with dependencies pre-installed so jobs don't reinstall Terraform, Helm, Ansible, etc. on every run. If the pool is unavailable for any reason, CI transparently falls back to GitHub-hosted runners and installs dependencies as before — no workflow breaks either way.

## Architecture

Two catalog apps, deployed only to `boa1-prod`:

- **`apps/github-runner-controller`** — [Actions Runner Controller](https://github.com/actions/actions-runner-controller) (ARC), the `gha-runner-scale-set-controller` chart. One instance, cluster-wide.
- **`apps/github-runner`** — the runner pool itself, the `gha-runner-scale-set` chart, configured with our custom image and `containerMode.type: dind` (a Docker-in-Docker sidecar, needed so `docker/build-push-action` in `build.yaml` has a real daemon to talk to). Runner scale set / `runs-on` label: `homescale-runners`.

Both apps share the `github-runner` namespace — safe because they're still two separate Helm releases/ArgoCD Applications (only *merging them into one chart* hit the naming bug below), and ARC's `controllerServiceAccount` value exists precisely to let the runner scale set reference the controller's ServiceAccount across releases. One gotcha from sharing: the catalog chart only applies `podSecurity` labels from the *first* app processed for a given namespace (by file glob order — see `docs/architecture/apps.md`), so both `app.yaml`s set `podSecurity: privileged` rather than relying on only the runner app to do it.

They're **not** merged into a single chart/Application, even though `gha-runner-scale-set-controller` and `gha-runner-scale-set` could technically be declared as two dependencies of one `Chart.yaml`: both charts independently define a generically-named internal Helm template (`gha-base-name`, meaning something different in each), and Helm's `define` blocks share one global namespace across a parent chart and its subcharts — combining them silently corrupted the runner scale set's resource names with the controller's naming. Confirmed by testing it; reverted.

`minRunners` is `3`, not `0`: with autoscale-to-zero, no runner would ever be registered while idle, and CI's "is the pool available" check (below) would have nothing to observe. Warm runners keep that check meaningful, avoid cold-start delay, and let multiple jobs run in parallel without falling back to cloud runners. `maxRunners` is `6`.

The runner scale set is registered at the **org** level (`githubConfigUrl: https://github.com/HomeScaleCloud`), so any repo in `HomeScaleCloud` can use the pool, not just `homescale`. This did briefly live at repo-scope (simpler API auth, see below) but there was no actual simplicity win to keep it there — the availability check already has to authenticate as a GitHub App regardless of scope (the default `GITHUB_TOKEN` can't list self-hosted runners at either scope, see below), so org-scope costs nothing extra and is strictly more useful.

## Setting it up

### 1. Create a GitHub App

In the `HomeScaleCloud` org → **Settings → Developer settings → GitHub Apps → New GitHub App**:

- Repository permissions: `Actions: Read-only`, `Administration: Read & write`
- Organization permissions: `Self-hosted runners: Read & write`
- No webhook, no user authorization needed
- Generate a private key (downloads a `.pem`)
- Install the app on the org (all repositories)

### 2. Add secrets to Infisical

At `/k8s/github-runner` (prod env):

| Key | Value |
|-----|-------|
| `github_app_id` | The App ID from the app's settings page |
| `github_app_installation_id` | The installation ID (visible in the URL after installing the app on the org) |
| `github_app_private_key` | The full contents of the downloaded `.pem` |

These are synced into the `github-runner` namespace as the `github-runner-github-app` secret by `apps/github-runner/templates/secret.yaml`, and referenced by the chart's `githubConfigSecret` value.

### 3. Make the runner image public

The `homescale` repo is private, so `ghcr.io/homescalecloud/github-runner` defaults to a private package on first push — which the cluster can't pull without an image pull secret. Since the image itself has no secrets baked in (just public tooling on top of the public `ghcr.io/actions/actions-runner` base), the simplest fix is to make the package public instead of managing a pull secret: after the first successful build (merge a change under `apps/github-runner/` to `main`), go to the package's settings on `github.com/orgs/HomeScaleCloud/packages` and change its visibility to public.

## How the CI fallback works

Every job in `scan.yaml`, `build.yaml`, `deploy.yaml`, and `mirror.yaml` depends on a `homescale-runners` job (`.github/workflows/homescale-runners.yaml`, itself a nested reusable workflow), which checks whether the pool has an online runner. Downstream jobs pick their `runs-on` from that result:

```yaml
runs-on: ${{ needs.homescale-runners.outputs.self_hosted == 'true' && 'homescale-runners' || 'ubuntu-latest' }}
```

Steps that install something the custom image already bakes in (Terraform, Helm, Ansible, mkdocs-material, git-filter-repo, etc.) are guarded the same way, so they only run on the GitHub-hosted fallback:

```yaml
if: needs.homescale-runners.outputs.self_hosted != 'true'
```

`claude.yml` (the `@claude` mention bot) intentionally does **not** go through this — it's not part of the build/test/deploy pipeline and has no heavy dependency-install steps to save.

### Auth: the default `GITHUB_TOKEN` cannot do this check at all

The check needs to call `GET /orgs/HomeScaleCloud/actions/runners`. The automatic `GITHUB_TOKEN` **cannot call this endpoint under any circumstances** — confirmed empirically via a temporary debug run: `403 Resource not accessible by integration`, even with `actions: read` correctly granted and propagated through the entire reusable-workflow call chain. This is a hard GitHub restriction on the ephemeral Actions token for runner-management endpoints specifically (true at repo scope too, not just org scope) — GitHub's documented fine-grained permission model (`actions: read` suffices) describes PAT/GitHub-App-token behavior, not `GITHUB_TOKEN`'s.

So the check authenticates as the same GitHub App used for runner registration instead, minting a short-lived org-scoped installation token via `actions/create-github-app-token` (credentials pulled from Infisical at `/k8s/github-runner`). Every step in that chain is defensive — if Infisical or the App auth fails for any reason, it falls back to the plain `GITHUB_TOKEN`, which will 403 against the org endpoint and correctly resolve to "unavailable" rather than error out.

This also means every reusable workflow in the call chain must grant **both** `actions: read` and `id-token: write` in its own top-level `permissions:` block — GitHub scopes what a called reusable workflow may request to the intersection of what every caller in the chain grants, checked at **workflow parse time**, not runtime. Missing either one doesn't just fail the check job at runtime — it fails the *entire run* at startup (`startup_failure`, before any job executes), since all referenced reusable workflows are validated upfront regardless of whether their job actually runs. This bit us twice: once via a mystery `startup_failure` with no useful error in the GitHub API (only visible by opening the run in the browser), and it turned out to be `mirror.yaml` missing `id-token: write`, even though the `mirror` job itself only runs on `push` events.

### Matching: ARC runners don't populate the classic `labels` field

The check matches on runner **name**, not `labels`:

```yaml
select(.name | startswith("homescale-runners-"))
```

ARC-managed runners report `labels: []` on this API regardless of scale set — verified against the live pool, every runner. ARC always names scale-set runners `<runnerScaleSetName>-<suffix>-runner-<suffix>`, so matching by name prefix is reliable.

### Failure modes

The check itself is defensive: any failure calling the GitHub API (rate limit, transient error, App auth failure) degrades to `self_hosted: false` rather than failing the `homescale-runners` job outright — since every other job `needs` it, a hard failure there would skip all of CI instead of just falling back to cloud runners. The one gap worth knowing about: the check runs once at the start of each workflow run, so if the pool disappears *mid-run* (rare — e.g. right after a passing check), a job already routed to `homescale-runners` will queue until it hits its own timeout rather than instantly falling back.

This means the pool being down, unreachable, or not yet set up is never a hard failure — CI just runs slower, exactly as it did before this pool existed.

## Tuning

- `minRunners` / `maxRunners` — set in `apps/github-runner/app.yaml` under `values.gha-runner-scale-set`.
- Dependencies baked into the runner image — `apps/github-runner/Dockerfile`. The Ansible collections are pulled from `infra/ansible/requirements.yml` (via `ansible-galaxy collection install -r`) rather than pinned separately in the Dockerfile, so there's nothing to keep in sync manually — the deployed image always reflects the current file.
- The image is tagged `:latest` rather than pinned to a git SHA (unlike the general convention for app images) so that a Dockerfile change rolls out on the next merge without a two-step PR dance — this is CI-internal infra, not a user-facing app.
- `python-is-python3` is installed explicitly. The base image only has `python3`; `pre-commit/action` (and potentially other third-party actions) hardcode `python`, which doesn't otherwise exist on PATH.

### Known issue: building this image on the pool itself can fail on network calls

Building `apps/github-runner` *on the `homescale-runners` pool* (as opposed to a GitHub-hosted runner) has intermittently failed on steps that fetch external resources during the Docker build — e.g. the `get-helm-3` install script hanging for 2–3 minutes before failing, reproduced 3/3 times in one investigation. A plain pod in the same namespace reaches the same URL in under 200ms, so it's not the pod's own network path — the leading hypothesis is an MTU mismatch between the dind sidecar's internal Docker bridge network and Cilium's VXLAN overlay (a known class of issue for Docker-in-Docker on Cilium clusters), but this hasn't been confirmed directly (inspecting the dind container's network config needs `pods/exec` in the `github-runner` namespace, which isn't broadly granted). If you hit this, retrying sometimes succeeds; if it's blocking a real merge, building on the GitHub-hosted fallback (temporarily disable the pool, or push a trivial unrelated commit to force cloud routing) is the workaround until this is root-caused.

### Trivy scan scope

`build.yaml`'s per-image Trivy scan (`skip-dirs`/`skip-files`, `github-runner`-specific) deliberately excludes: everything bundled by the `ghcr.io/actions/actions-runner` base image itself (`docker`/`containerd`/`runc`/`buildx`, its own Node.js toolchain under `home/runner/externals`), and the five tools this Dockerfile installs as the latest official release from their own channel (`gh`, `tailscale`, `terraform`, `helm`, `kubectl`). Every finding hit there so far has been the same shape — an official upstream binary statically compiled with a Go (or Node) stdlib version a few patches behind the latest security fix, with no newer release to pin to instead. That's accepted supply-chain risk inherent to depending on these tools at all, not something fixable from this Dockerfile; the scan still catches anything in packages we actually pin ourselves (the `pip3 install` block).

### Building the image locally

`infra/ansible/requirements.yml` lives outside `apps/github-runner/`, and Docker can't `COPY` from outside its build context, so `build.yaml`'s `docker` job copies it in (`apps/github-runner/requirements.yml`, gitignored) right before building. Do the same locally first:

```bash
cp infra/ansible/requirements.yml apps/github-runner/requirements.yml
docker build apps/github-runner -t github-runner
```
