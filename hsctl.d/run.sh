#!/usr/bin/env bash
# hsctl run — run an Ansible playbook from infra/ansible/playbooks/, either locally or
# remotely as a one-off Kubernetes Job on automatron (apps/automatron).
#
# bootstrap-core/bootstrap-cluster get special local-secrets handling (see
# _run_bootstrap_local); any other playbook runs as-is with no Infisical fallback of its
# own, so a new one needing local secrets must add hsctl_local-aware handling itself.
#
# Local mode never runs against $HSCTL_REPO_ROOT — it clones HomeScaleCloud/homescale@main
# fresh into a temp dir instead (_run_local_clone_repo), so it always matches main.

_run_bootstrap_playbooks=(bootstrap-core bootstrap-cluster)

# Cleanup registry: a later `trap ... EXIT` call replaces any earlier one instead of
# stacking, so independent cleanups register a path here rather than trapping directly.
_run_cleanup_paths=()
_run_register_cleanup() { _run_cleanup_paths+=("$1"); }
_run_cleanup() {
    local p
    for p in "${_run_cleanup_paths[@]:-}"; do
        [[ -n "$p" ]] && rm -rf "$p"
    done
}
trap _run_cleanup EXIT

run_usage() {
    echo "Usage: hsctl run <name> [--cluster <name>] [-e|--execution-mode local|remote] [--dry-run] [--chain <name>[,<name>...]]"
    echo ""
    echo "In remote mode (default), <name> is the name of an AutomatronJobTemplate CR (see"
    echo "infra/automatron/job-templates/ and CLAUDE.md's Automatron section)."
    echo ""
    echo "In local mode, <name> is any filename (without .yml) under infra/ansible/playbooks/, e.g.:"
    echo "  bootstrap-core      bootstrap the core cluster"
    echo "  bootstrap-cluster   bootstrap workload clusters (all, or one via --cluster)"
    echo "  omni-sync           sync every cluster template + machine class into Omni"
    echo ""
    echo "Options:"
    echo "  --cluster <name>            passed through as the run's cluster override; meaningful"
    echo "                              for bootstrap-cluster (its Omni cluster ID, e.g. boa1-prod)"
    echo "  -e, --execution-mode <mode> 'local' or 'remote' (default: remote). remote creates a"
    echo "                              JobRun CR on automatron (in the core cluster) and streams"
    echo "                              the resulting Job's logs; requires a Tailscale-reachable"
    echo "                              core apiserver and team-infra-plat/team-sec-plat membership"
    echo "                              (no PIM needed). local clones main fresh (via gh) into a"
    echo "                              temp dir and runs ansible-playbook against that — still"
    echo "                              required for the very first core bootstrap, before"
    echo "                              automatron exists to dispatch to."
    echo "  --dry-run                   passed through as a dry-run override; only omni-sync acts"
    echo "                              on it today (adds --dry-run to its omnictl calls)"
    echo "  --chain <name>[,...]        after <name> succeeds, run each of these in turn"
    echo "                              (comma-separated, no spaces), stopping at the first failure."
    echo "                              In -e remote mode this is the same mechanism a scheduled"
    echo "                              JobTemplate's own spec.chain uses (see entrypoint.sh) —"
    echo "                              each hop gets its own JobRun/Job, and this command follows"
    echo "                              each one's pod logs in turn as they're created. In -e local"
    echo "                              mode they just run sequentially against the same checkout."
    exit 1
}

# Fetch a secrets folder from Infisical via the caller's already-authenticated CLI session,
# retrying once through an interactive login if the session is invalid/expired.
# Usage: _run_infisical_secrets <path>   -> flat JSON object {KEY: value, ...} on stdout
_run_infisical_secrets() {
    local path="$1" raw
    if ! raw=$(infisical export --silent --env=prod --path="$path" --format=json </dev/null); then
        hsctl_infisical_login || { hsctl_log_error "infisical login failed"; return 1; }
        if ! raw=$(infisical export --silent --env=prod --path="$path" --format=json </dev/null); then
            hsctl_log_error "failed to fetch secrets from Infisical (path $path)"
            return 1
        fi
    fi
    jq 'map({(.key): .value}) | add // {}' <<< "$raw"
}

# Run bootstrap-core or bootstrap-cluster locally, pre-fetching secrets via the local
# Infisical CLI session and handing them to Ansible as hsctl_local_secrets.
_run_bootstrap_local() {
    local playbook="$1" cluster="$2" dry_run="$3" repo_root="$4"

    command -v infisical &>/dev/null || { echo "hsctl run: the infisical CLI is required (brew install infisical)" >&2; exit 1; }
    command -v jq &>/dev/null || { echo "hsctl run: jq is required (brew install jq)" >&2; exit 1; }

    [[ -n "$cluster" && "$playbook" == "bootstrap-core" ]] && hsctl_log_info "--cluster is ignored for bootstrap-core"

    hsctl_log_info "fetching secrets from Infisical via local CLI session"
    local argocd_secrets infisical_op_secrets core_kubeconfig_secrets='{}'
    argocd_secrets=$(_run_infisical_secrets /k8s/argocd/deploy-key) || exit 1
    infisical_op_secrets=$(_run_infisical_secrets /k8s/infisical) || exit 1
    [[ "$playbook" == "bootstrap-core" ]] && { core_kubeconfig_secrets=$(_run_infisical_secrets /k8s/automatron) || exit 1; }

    local extra_vars_file
    extra_vars_file=$(mktemp)
    chmod 600 "$extra_vars_file"
    _run_register_cleanup "$extra_vars_file"

    jq -n \
        --argjson argocd "$argocd_secrets" \
        --argjson infisical_op "$infisical_op_secrets" \
        --argjson core_kubeconfig "$core_kubeconfig_secrets" \
        '{hsctl_local: true, hsctl_local_secrets: {argocd_deploy_key: $argocd, infisical_operator: $infisical_op, core_kubeconfig: $core_kubeconfig}}' \
        > "$extra_vars_file"

    (
        export HSCTL_REPO_ROOT="$repo_root" # so a nested `hsctl get machines` (via omni.py) resolves against the same fresh checkout
        cd "$repo_root/infra/ansible" || exit 1

        case "$playbook" in
            bootstrap-core)
                hsctl_log_action "running bootstrap-core.yml"
                ansible-playbook playbooks/bootstrap-core.yml -e cluster_name=core -e "dry_run=$dry_run" --extra-vars "@$extra_vars_file"
                ;;
            bootstrap-cluster)
                hsctl_log_action "running bootstrap-cluster.yml${cluster:+ (target: $cluster)}"
                if [[ -n "$cluster" ]]; then
                    ansible-playbook playbooks/bootstrap-cluster.yml -e target="$cluster" -e "dry_run=$dry_run" --extra-vars "@$extra_vars_file"
                else
                    ansible-playbook playbooks/bootstrap-cluster.yml -e "dry_run=$dry_run" --extra-vars "@$extra_vars_file"
                fi
                ;;
        esac
    )
}

# Run any other playbook locally, as-is — no local secrets handling (see module comment).
_run_generic_local() {
    local playbook="$1" cluster="$2" dry_run="$3" repo_root="$4"
    local playbook_file="$repo_root/infra/ansible/playbooks/$playbook.yml"

    [[ -f "$playbook_file" ]] || { hsctl_log_error "no such playbook: infra/ansible/playbooks/$playbook.yml"; exit 1; }

    (
        export HSCTL_REPO_ROOT="$repo_root" # so a nested `hsctl get machines` (via omni.py) resolves against the same fresh checkout
        cd "$repo_root/infra/ansible" || exit 1
        hsctl_log_action "running $playbook.yml${cluster:+ (target: $cluster)}"
        if [[ -n "$cluster" ]]; then
            ansible-playbook "playbooks/$playbook.yml" -e target="$cluster" -e "dry_run=$dry_run"
        else
            ansible-playbook "playbooks/$playbook.yml" -e "dry_run=$dry_run"
        fi
    )
}

# Clones `main` fresh into a temp dir, once per `hsctl run` invocation (not per chained
# playbook). Doesn't call _run_register_cleanup itself — this runs in a $(...) subshell,
# so the caller registers the returned path in its own, non-subshell scope instead.
_run_local_clone_repo() {
    command -v gh &>/dev/null || { echo "hsctl run: gh is required for local runs (brew install gh)" >&2; exit 1; }

    local tmpdir
    tmpdir=$(mktemp -d)
    if ! gh repo clone HomeScaleCloud/homescale "$tmpdir" -- --depth 1 --branch main --quiet; then
        hsctl_log_error "failed to clone HomeScaleCloud/homescale@main (check: gh auth status)"
        rm -rf "$tmpdir"
        return 1
    fi
    echo "$tmpdir"
}

_run_local() {
    local playbook="$1" cluster="$2" dry_run="$3" repo_root="$4"

    command -v ansible-playbook &>/dev/null || { echo "hsctl run: ansible-playbook is required (pip install ansible)" >&2; exit 1; }

    if [[ " ${_run_bootstrap_playbooks[*]} " == *" $playbook "* ]]; then
        _run_bootstrap_local "$playbook" "$cluster" "$dry_run" "$repo_root"
    else
        _run_generic_local "$playbook" "$cluster" "$dry_run" "$repo_root"
    fi
}

# _run_stream_job <job_name> <namespace> — wait for the Job's pod, stream its logs, wait
# for the Job to finish. Returns 0 on success, 1 on failure/timeout (with an error already
# logged) — never exits itself, so callers streaming a chain of jobs can stop at whichever
# one actually failed rather than the whole function call stack unwinding silently.
_run_stream_job() {
    local job_name="$1" namespace="$2"

    hsctl_log_info "waiting for the pod to appear..."
    local attempt pod=""
    for attempt in $(seq 1 30); do
        sleep 2
        pod=$(kubectl get pods -n "$namespace" --context core -l "job-name=$job_name" \
            -o jsonpath='{.items[0].metadata.name}' 2>/dev/null) || true
        [[ -n "$pod" ]] && break
    done

    if [[ -z "$pod" ]]; then
        hsctl_log_error "pod never appeared — check: kubectl get pods -n $namespace --context core -l job-name=$job_name"
        return 1
    fi

    # `kubectl logs -f` errors immediately if called before the container has started
    # (it sits behind the git-key-prep/git-clone initContainers), so poll until it has.
    hsctl_log_info "waiting for the automatron container to start..."
    local started=""
    for attempt in $(seq 1 60); do
        started=$(kubectl get pod "$pod" -n "$namespace" --context core \
            -o jsonpath='{.status.containerStatuses[?(@.name=="automatron")].started}' 2>/dev/null) || true
        [[ "$started" == "true" ]] && break
        sleep 3
    done

    if [[ "$started" != "true" ]]; then
        hsctl_log_error "automatron container never started — check: kubectl describe pod $pod -n $namespace --context core"
        return 1
    fi

    # kubecolor, if present, colorizes this like an interactive `kubectl logs` would;
    # every other kubectl call above parses structured output and must stay plain.
    local log_cmd="kubectl"
    command -v kubecolor &>/dev/null && log_cmd="kubecolor"
    "$log_cmd" logs -f "$pod" -c automatron -n "$namespace" --context core

    # The Job controller can lag behind the log stream closing, so poll briefly for
    # .status rather than checking once immediately.
    local succeeded="" failed=""
    for attempt in $(seq 1 10); do
        succeeded=$(kubectl get job "$job_name" -n "$namespace" --context core \
            -o jsonpath='{.status.succeeded}' 2>/dev/null) || true
        failed=$(kubectl get job "$job_name" -n "$namespace" --context core \
            -o jsonpath='{.status.failed}' 2>/dev/null) || true
        [[ "$succeeded" == "1" || -n "$failed" ]] && break
        sleep 3
    done

    if [[ "$succeeded" != "1" ]]; then
        hsctl_log_error "job $job_name did not succeed — check: kubectl describe job $job_name -n $namespace --context core"
        return 1
    fi
    hsctl_log_success "job $job_name completed"
}

# _run_wait_for_chained_job <chain_root> <template> <namespace> — poll for the Job that
# entrypoint.sh's chaining creates for <template> as part of the chain rooted at
# <chain_root> (see rgd-jobrun.yaml's chain-root/template labels), printing its name on
# stdout once found. Playbooks can take a while, so this waits up to ~2 minutes.
_run_wait_for_chained_job() {
    local chain_root="$1" template="$2" namespace="$3"
    local attempt job_name=""
    for attempt in $(seq 1 60); do
        job_name=$(kubectl get jobs -n "$namespace" --context core \
            -l "REDACTED/chain-root=$chain_root,REDACTED/template=$template" \
            -o jsonpath='{.items[0].metadata.name}' 2>/dev/null) || true
        [[ -n "$job_name" ]] && { echo "$job_name"; return 0; }
        sleep 2
    done
    return 1
}

_run_remote() {
    local name="$1" cluster="$2" dry_run="$3" chain_raw="$4"
    local namespace="automatron"
    local run_name="automatron-adhoc-${name}-$(date +%s)"

    command -v kubectl &>/dev/null || { echo "hsctl run: kubectl is required" >&2; exit 1; }
    command -v jq &>/dev/null || { echo "hsctl run: jq is required (brew install jq)" >&2; exit 1; }

    # A `core` context, if already present, is reused via explicit --context core below.
    # Otherwise, authenticate via OIDC (hsctl get kubeconfig), which switches
    # current-context as a side effect — restore it immediately after.
    if ! kubectl config get-contexts -o name 2>/dev/null | grep -qx core; then
        local prev_ctx
        prev_ctx=$(kubectl config current-context 2>/dev/null || true)
        # shellcheck source=/dev/null
        source "$HSCTL_ROOT/hsctl.d/get.sh"
        hsctl_log_info "no core context found — authenticating via OIDC"
        get_kubeconfig core >/dev/null
        [[ -n "$prev_ctx" ]] && kubectl config use-context "$prev_ctx" >/dev/null 2>&1
    fi

    # JobTemplate/JobRun are cluster-scoped (single automatron install per cluster, no
    # per-namespace isolation needed), so these `kubectl get`/`create` calls take no `-n`
    # — only the native Job/Pod calls in _run_stream_job do.
    kubectl get jobtemplate "$name" --context core &>/dev/null || {
        hsctl_log_error "no such JobTemplate: $name (check: kubectl get jobtemplate --context core)"
        exit 1
    }

    hsctl_log_action "creating JobRun $run_name (template=$name${cluster:+, cluster=$cluster}${dry_run:+, dry_run=$dry_run}${chain_raw:+, chain=$chain_raw}) on automatron"
    jq -n --arg name "$run_name" --arg template "$name" --arg cluster "$cluster" \
        --argjson dryrun "$dry_run" --arg chain "$chain_raw" '
      {apiVersion: "REDACTED/v1alpha1", kind: "JobRun",
       metadata: {name: $name},
       spec: {templateRef: $template, cluster: $cluster, dryRun: $dryrun, chain: $chain}}' \
        | kubectl create --context core -f -

    hsctl_log_info "waiting for Automatron to materialize the Job..."
    local attempt job_name=""
    for attempt in $(seq 1 30); do
        job_name=$(kubectl get jobrun "$run_name" --context core \
            -o jsonpath='{.status.jobName}' 2>/dev/null) || true
        [[ -n "$job_name" ]] && break
        sleep 2
    done

    if [[ -z "$job_name" ]]; then
        hsctl_log_error "JobRun $run_name never produced a Job — check: kubectl describe jobrun $run_name --context core"
        exit 1
    fi

    _run_stream_job "$job_name" "$namespace" || exit 1

    # --chain: entrypoint.sh's own chaining creates the next hop's JobRun one at a time
    # (same mechanism a scheduled JobTemplate's spec.chain uses) — this run's own JobRun
    # name is the chain root (rgd-jobrun.yaml defaults spec.chainRoot to it when unset),
    # so follow along and stream each subsequent hop's logs too as they appear.
    if [[ -n "$chain_raw" ]]; then
        local chain_templates=() next_template
        local IFS=','
        read -r -a chain_templates <<< "$chain_raw"
        unset IFS
        for next_template in "${chain_templates[@]}"; do
            hsctl_log_info "waiting for chained JobRun (template=$next_template)..."
            job_name=$(_run_wait_for_chained_job "$run_name" "$next_template" "$namespace") || {
                hsctl_log_error "no Job appeared for chained template $next_template (chain root: $run_name) — check: kubectl get jobs -l REDACTED/chain-root=$run_name --context core"
                exit 1
            }
            _run_stream_job "$job_name" "$namespace" || exit 1
        done
    fi
}

run_main() {
    local playbook="" cluster="" mode="remote" dry_run="false" playbook_set=false
    local chain_raw=""

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --cluster) cluster="${2:-}"; [[ -z "$cluster" ]] && run_usage; shift 2 ;;
            -e|--execution-mode)
                mode="${2:-}"
                [[ "$mode" != "local" && "$mode" != "remote" ]] && run_usage
                shift 2 ;;
            --dry-run) dry_run="true"; shift ;;
            --chain)
                chain_raw="${2:-}"; [[ -z "$chain_raw" ]] && run_usage
                shift 2 ;;
            -h|--help) run_usage ;;
            --*) echo "hsctl run: unknown flag '$1'" >&2; run_usage ;;
            *)
                [[ "$playbook_set" == true ]] && { echo "hsctl run: unexpected argument '$1'" >&2; run_usage; }
                playbook="$1"; playbook_set=true; shift ;;
        esac
    done

    [[ -z "$playbook" ]] && { echo "hsctl run: a name is required" >&2; run_usage; }

    local local_repo_root=""
    if [[ "$mode" == "local" ]]; then
        local_repo_root=$(_run_local_clone_repo) || exit 1
        _run_register_cleanup "$local_repo_root"
    fi

    if [[ "$mode" == "remote" ]]; then
        _run_remote "$playbook" "$cluster" "$dry_run" "$chain_raw"
    else
        local chain_templates=() p
        if [[ -n "$chain_raw" ]]; then
            local IFS=','
            read -r -a chain_templates <<< "$chain_raw"
            unset IFS
        fi
        for p in "$playbook" "${chain_templates[@]:-}"; do
            [[ -z "$p" ]] && continue
            _run_local "$p" "$cluster" "$dry_run" "$local_repo_root"
        done
    fi
}
