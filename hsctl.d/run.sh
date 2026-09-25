#!/usr/bin/env bash
# hsctl run — run an Ansible playbook from infra/automatron/ansible/playbooks/, either locally or
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
    # An EXIT trap's own final exit status silently overwrites the script's real one — with
    # an empty _run_cleanup_paths (always true in remote mode), the loop's last evaluated
    # command is `[[ -n "" ]]` (false), so without this, every single successful -e remote
    # run exited 1 regardless — confirmed live, this is what made deploy.yaml's "Plan via
    # automatron" step (set -euo pipefail | tee ...) report failure on a genuinely clean
    # terraform plan with zero errors.
    return 0
}
trap _run_cleanup EXIT

run_usage() {
    echo "Usage: hsctl run <name> [--cluster <name>] [--arg key=value]... [-e|--execution-mode local|remote] [--dry-run] [--chain <name>[,<name>...]] [--git-ref <ref>]"
    echo ""
    echo "In remote mode (default), <name> is the name of an AutomatronJobTemplate or"
    echo "AutomatronJobWorkflow CR (see infra/automatron/job-templates/, infra/automatron/"
    echo "job-workflows/, and CLAUDE.md's Automatron section) — hsctl checks JobTemplate first,"
    echo "then JobWorkflow. Every Job/JobRun/JobWorkflowRun this creates is named with the JobTemplate"
    echo "actually being executed (not just a step number), and labeled"
    echo "REDACTED/job-owner with your identity: \$HSCTL_JOB_OWNER if set (CI sets"
    echo "HSCTL_JOB_OWNER=ci), else your OIDC email's local part (e.g. 'max' for"
    echo "max@REDACTED), else your local username; a scheduled run is labeled 'schedule'."
    echo ""
    echo "In local mode, <name> is any filename (without .yml) under infra/automatron/ansible/playbooks/, e.g.:"
    echo "  bootstrap-core      bootstrap the core cluster"
    echo "  bootstrap-cluster   bootstrap workload clusters (all, or one via --cluster)"
    echo "  omni-sync           sync every cluster template + machine class into Omni"
    echo ""
    echo "Options:"
    echo "  --arg key=value             (repeatable, remote mode only) sets an arbitrary extra-var/"
    echo "                              script argument, passed to the playbook or script wholesale"
    echo "                              — nothing here is automatron-specific, any key the playbook"
    echo "                              or script expects works. For a JobWorkflow (or an ad hoc"
    echo "                              --chain), applies to every step that doesn't already set"
    echo "                              that key itself — a step's own value (if the workflow"
    echo "                              declares one) always wins; this flag always wins over the"
    echo "                              step's JobTemplate's own defaultArgs."
    echo "  --cluster <name>            sugar for --arg cluster=<name> — the one arg key common"
    echo "                              enough to deserve its own flag; meaningful for"
    echo "                              bootstrap-cluster (its Omni cluster ID, e.g. boa1-prod)"
    echo "  -e, --execution-mode <mode> 'local' or 'remote' (default: remote). remote creates a"
    echo "                              JobRun CR on automatron (in the core cluster) and streams"
    echo "                              the resulting Job's logs; requires a Tailscale-reachable"
    echo "                              core apiserver and team-infra-plat/team-sec-plat membership"
    echo "                              (no PIM needed). local clones main fresh (via gh) into a"
    echo "                              temp dir and runs ansible-playbook against that — still"
    echo "                              required for the very first core bootstrap, before"
    echo "                              automatron exists to dispatch to; only understands --cluster,"
    echo "                              not --arg, since it doesn't go through automatron's CRDs."
    echo "  --dry-run                   see --arg above for precedence; only omni-sync acts on this"
    echo "                              today (adds --dry-run to its omnictl calls)"
    echo "  --chain <name>[,...]        <name> must be a JobTemplate (not a JobWorkflow, which"
    echo "                              already declares its own steps); builds an ad hoc,"
    echo "                              uncommitted JobWorkflow out of <name> plus this list"
    echo "                              (comma-separated, no spaces), applying --arg/--cluster/"
    echo "                              --dry-run to every step, then runs it like any other"
    echo "                              JobWorkflow (creating a JobWorkflowRun that references it)."
    echo "                              In -e remote mode this creates a JobRun per step, one at a"
    echo "                              time (see entrypoint.sh), and this command follows each"
    echo "                              one's pod logs in turn, stopping at the first failure. In"
    echo "                              -e local mode they just run sequentially against the same"
    echo "                              checkout, no JobWorkflow/JobWorkflowRun involved."
    echo "  --git-ref <ref>              (remote mode only, default: main) branch/tag/SHA for the"
    echo "                              JobRun's own git-clone initContainer to check out instead of"
    echo "                              main — the one real use is planning a PR's own uncommitted"
    echo "                              changes (deploy.yaml's PR-time Omni plan uses this); every"
    echo "                              other caller leaves it at main so scheduled/production runs"
    echo "                              always reflect what's actually merged. For a chain/workflow,"
    echo "                              applies to every step (propagated by entrypoint.sh)."
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
        export HSCTL_REPO_ROOT="$repo_root" # so a nested `hsctl get machines` (via the inventory/machines dynamic inventory script) resolves against the same fresh checkout
        cd "$repo_root/infra/automatron/ansible" || exit 1

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
    local playbook_file="$repo_root/infra/automatron/ansible/playbooks/$playbook.yml"

    [[ -f "$playbook_file" ]] || { hsctl_log_error "no such playbook: infra/automatron/ansible/playbooks/$playbook.yml"; exit 1; }

    (
        export HSCTL_REPO_ROOT="$repo_root" # so a nested `hsctl get machines` (via the inventory/machines dynamic inventory script) resolves against the same fresh checkout
        cd "$repo_root/infra/automatron/ansible" || exit 1
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
    # Checking `.started == true` alone isn't enough: a container that fails within its
    # first second or so (e.g. a bad JobTemplate producing neither PLAYBOOK nor SCRIPT_PATH)
    # can go straight from not-yet-started to `state.terminated` without the kubelet ever
    # reporting `started: true` in between — confirmed live, .started stayed false on a pod
    # whose automatron container had already terminated with a real exitCode/reason. Treat
    # `state.terminated` being set as equally sufficient to proceed (kubectl logs on an
    # already-terminated container just dumps what it wrote and returns, no -f hang), and
    # fail fast on a `state.waiting` reason that will never resolve on its own instead of
    # waiting out the full timeout for something already showing why it's stuck.
    hsctl_log_info "waiting for the automatron container to start..."
    local started="false" terminated="false" waiting_reason=""
    for attempt in $(seq 1 60); do
        local cs
        cs=$(kubectl get pod "$pod" -n "$namespace" --context core -o json 2>/dev/null | \
            jq -c '.status.containerStatuses[]? | select(.name=="automatron")') || true
        # NOT `${cs:-{}}` — bash's scanner for a ${VAR:-word} default misjudges where the
        # substitution ends when word contains a literal {}, corrupting the value even when
        # $cs is already set to real content (see entrypoint.sh's own ARGS_JSON for the same
        # gotcha) — confirmed live here too, jq errored on the resulting garbage.
        [[ -z "$cs" ]] && cs='{}'
        started=$(jq -r '.started // false' <<<"$cs" 2>/dev/null) || started="false"
        terminated=$(jq -r 'has("state") and (.state | has("terminated"))' <<<"$cs" 2>/dev/null) || terminated="false"
        waiting_reason=$(jq -r '.state.waiting.reason // empty' <<<"$cs" 2>/dev/null) || waiting_reason=""
        [[ "$started" == "true" || "$terminated" == "true" ]] && break
        case "$waiting_reason" in
            ImagePullBackOff|ErrImagePull|InvalidImageName|CreateContainerConfigError|CreateContainerError)
                hsctl_log_error "automatron container stuck ($waiting_reason) — check: kubectl describe pod $pod -n $namespace --context core"
                return 1 ;;
        esac
        sleep 3
    done

    if [[ "$started" != "true" && "$terminated" != "true" ]]; then
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

# _run_wait_for_workflow_step <run_name> <step_index> — poll for the JobRun belonging to
# JobWorkflowRun <run_name> at position <step_index> (see rgd-jobrun.yaml's workflow-run
# label; rgd-jobworkflow.yaml's kickoff container creates step 0, entrypoint.sh creates
# every step after that) to produce a Job, printing that Job's name on stdout once found.
# Playbooks can take a while, so this waits up to ~2 minutes per step.
_run_wait_for_workflow_step() {
    local run_name="$1" step_index="$2"
    local attempt job_name=""
    for attempt in $(seq 1 60); do
        job_name=$(kubectl get jobrun --context core \
            -l "REDACTED/workflow-run=$run_name" -o json 2>/dev/null | \
            jq -r --argjson idx "$step_index" '.items[] | select(.spec.stepIndex == $idx) | .status.jobName // empty') || true
        [[ -n "$job_name" ]] && { echo "$job_name"; return 0; }
        sleep 2
    done
    return 1
}

# _run_resolve_workflow_steps <cli-args-json> <dry_run> <json-steps-array> — apply the
# precedence rule (a step's own args always win, key by key; else the hsctl --arg/--cluster
# CLI-supplied args, if this is an ad hoc run; else leave a key unset and let JobRun's own
# CEL map.merge() fall back to the step's JobTemplate's defaultArgs) to every step,
# printing the resolved JSON array on stdout. dryRun has no empty-ish sentinel to detect
# "unset" the way an args key's absence does, so it's just OR'd — true from either side
# wins, since nothing here ever needs to force a false over an explicit true from the
# other side.
_run_resolve_workflow_steps() {
    local cli_args_json="$1" dry_run="$2" steps_json="$3"
    echo "$steps_json" | jq --argjson cli "$cli_args_json" --argjson dryrun "$dry_run" '
        map(. + {
            args: ($cli + (.args // {})),
            dryRun: ((.dryRun // false) or $dryrun)
        })'
}

# _run_job_owner — identity to name/label ad hoc runs with: $HSCTL_JOB_OWNER if set
# (deploy.yaml sets this to "ci" for CI-triggered runs), else the HomeScale OIDC
# identity (hsctl_oidc_username, in _lib.sh — decodes the same kubelogin id_token the `core`
# context's exec plugin already mints, reading issuer/client-id straight out of the local
# kubeconfig, no Infisical involved). Deliberately has no whoami/local-username fallback —
# local usernames routinely don't match the @REDACTED identity closely enough to trust
# for an ownership/audit label, so a wrong-but-plausible-looking value is worse than a loud
# failure here. Callers must ensure a `core` context already exists (see _run_remote) before
# calling this. Sanitized for use in both a label value and a Job/CR name component (lowercase,
# alphanumeric-and-hyphens only, no leading/trailing/repeated hyphens).
_run_job_owner() {
    local owner="${HSCTL_JOB_OWNER:-}"
    [[ -z "$owner" ]] && owner=$(hsctl_oidc_username 2>/dev/null || true)
    if [[ -z "$owner" ]]; then
        hsctl_log_error "could not determine your identity for job-owner attribution (no \$HSCTL_JOB_OWNER, and OIDC lookup failed — is a 'core' kubectl context configured? try 'hsctl get kubeconfig core')"
        exit 1
    fi
    echo "$owner" | tr '[:upper:]' '[:lower:]' | tr -c 'a-z0-9-' '-' | sed 's/-\{2,\}/-/g; s/^-//; s/-$//'
}

# _run_truncate — caps a run_name component at 16 chars (stripping any trailing hyphen the
# cut leaves dangling, since a Kubernetes name/label value can't end in one). See run_name's
# own comment in _run_remote for why this matters.
_run_truncate() {
    local s="${1:0:16}"
    echo "${s%-}"
}

_run_remote() {
    local name="$1" cli_args_json="$2" dry_run="$3" chain_raw="$4" git_ref="${5:-main}"
    local namespace="automatron"

    command -v kubectl &>/dev/null || { echo "hsctl run: kubectl is required" >&2; exit 1; }
    command -v jq &>/dev/null || { echo "hsctl run: jq is required (brew install jq)" >&2; exit 1; }

    # A `core` context, if already present, is reused via explicit --context core below.
    # Otherwise, authenticate via OIDC (hsctl get kubeconfig), which switches
    # current-context as a side effect — restore it immediately after. Must happen before
    # _run_job_owner: its OIDC lookup reads the issuer/client-id straight out of this context's
    # exec config, so it needs to exist first.
    if ! kubectl config get-contexts -o name 2>/dev/null | grep -qx core; then
        local prev_ctx
        prev_ctx=$(kubectl config current-context 2>/dev/null || true)
        # shellcheck source=/dev/null
        source "$HSCTL_ROOT/hsctl.d/get.sh"
        hsctl_log_info "no core context found — authenticating via OIDC"
        get_kubeconfig core >/dev/null
        [[ -n "$prev_ctx" ]] && kubectl config use-context "$prev_ctx" >/dev/null 2>&1
    fi

    local job_owner
    job_owner=$(_run_job_owner)

    # One name for this whole invocation, reused as-is for whichever object ends up being
    # the "root" of it (the JobRun, for a plain single-template run; the JobWorkflowRun,
    # for a workflow or chain) — and, for an ad hoc --chain, also for the throwaway
    # JobWorkflow created below (a JobWorkflow and a JobWorkflowRun are different kinds, so
    # sharing one name between them isn't a collision). Both components are truncated: this
    # name gets reused as a label VALUE (REDACTED/workflow[-run]), not
    # just an object name, and Kubernetes caps label values at 63 bytes — confirmed live,
    # an untruncated name (job_owner=ci + a longer template/workflow name)
    # broke both kro's own label-selector reconciliation and hsctl's own kubectl creates.
    # No "atm-"/"automatron-" prefix here — these are CR names (JobRun/JobWorkflowRun/
    # JobWorkflow), and `kubectl get jobrun`/etc. already makes plain what kind of object
    # you're looking at. rgd-jobrun.yaml prepends "atm-" itself, only on the native Job/Pod
    # it creates from this JobRun (a Job/Pod sits in a flat namespace among unrelated
    # objects, so *that's* what needs the at-a-glance marker) — leave headroom for those 4
    # bytes in any budget computed from this name (see step0_name below).
    local run_name="$(_run_truncate "$job_owner")-$(_run_truncate "$name")-$(date +%s)"

    # Every automatron CRD is cluster-scoped (single automatron install per cluster, no
    # per-namespace isolation needed), so these `kubectl get`/`create` calls take no `-n`
    # — only the native Job/Pod calls in _run_stream_job do.
    local resolved_steps="" workflow_ref=""
    if kubectl get jobtemplate "$name" --context core &>/dev/null; then
        if [[ -n "$chain_raw" ]]; then
            resolved_steps=$(jq -n --arg first "$name" --arg rest "$chain_raw" '
                [$first] + ($rest | split(","))
                | map({templateRef: ., args: {}, dryRun: false})')
            resolved_steps=$(_run_resolve_workflow_steps "$cli_args_json" "$dry_run" "$resolved_steps")

            # Standardize on JobWorkflowRun always being an instance of a real JobWorkflow
            # (never an empty workflowRef) — an ad hoc --chain creates a throwaway one, with
            # the already-fully-resolved step list baked in, same as any committed one.
            hsctl_log_action "creating ad hoc JobWorkflow $run_name ($(echo "$resolved_steps" | jq 'length') steps) on automatron"
            jq -n --arg name "$run_name" --argjson steps "$resolved_steps" --arg owner "$job_owner" '
              {apiVersion: "REDACTED/v1alpha1", kind: "JobWorkflow",
               metadata: {name: $name, labels: {"REDACTED/job-owner": $owner, "REDACTED/adhoc": "true"}},
               spec: {steps: $steps}}' | kubectl create --context core -f -
            workflow_ref="$run_name"
        fi
    elif kubectl get jobworkflow "$name" --context core &>/dev/null; then
        [[ -n "$chain_raw" ]] && { hsctl_log_error "--chain isn't meaningful for a JobWorkflow — $name already declares its own steps"; exit 1; }
        workflow_ref="$name"
        local declared_steps
        declared_steps=$(kubectl get jobworkflow "$name" --context core -o json | jq -c '.spec.steps')
        [[ "$declared_steps" == "[]" || -z "$declared_steps" ]] && { hsctl_log_error "workflow $name has no steps"; exit 1; }
        resolved_steps=$(_run_resolve_workflow_steps "$cli_args_json" "$dry_run" "$declared_steps")
    else
        hsctl_log_error "no such JobTemplate or JobWorkflow: $name (check: kubectl get jobtemplate,jobworkflow --context core)"
        exit 1
    fi

    if [[ -z "$resolved_steps" ]]; then
        # Plain single-template run — no chain, no workflow.
        hsctl_log_action "creating JobRun $run_name (template=$name, args=$cli_args_json${dry_run:+, dry_run=$dry_run}${git_ref:+, git_ref=$git_ref}) on automatron"
        jq -n --arg name "$run_name" --arg template "$name" --argjson args "$cli_args_json" --argjson dryrun "$dry_run" --arg owner "$job_owner" --arg ref "$git_ref" '
          {apiVersion: "REDACTED/v1alpha1", kind: "JobRun",
           metadata: {name: $name, labels: {"REDACTED/job-owner": $owner}},
           spec: {templateRef: $template, args: $args, dryRun: $dryrun, jobOwner: $owner, gitRef: $ref}}' \
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
        return
    fi

    # Multi-step: create a JobWorkflowRun with the fully-resolved step list, plus step 0's
    # JobRun — entrypoint.sh creates every step after that on success (see CLAUDE.md) —
    # then follow along, streaming each step's pod logs in turn as they're created.
    local total_steps
    total_steps=$(echo "$resolved_steps" | jq 'length')

    hsctl_log_action "creating JobWorkflowRun $run_name (${workflow_ref:+workflow=$workflow_ref, }$total_steps steps) on automatron"
    jq -n --arg name "$run_name" --arg wf "$workflow_ref" --argjson steps "$resolved_steps" --arg owner "$job_owner" '
      {apiVersion: "REDACTED/v1alpha1", kind: "JobWorkflowRun",
       metadata: {name: $name, labels: {"REDACTED/workflow": $wf, "REDACTED/job-owner": $owner}},
       spec: {workflowRef: $wf, steps: $steps, jobOwner: $owner}}' | kubectl create --context core -f -

    local step0_template step0_name
    step0_template=$(echo "$resolved_steps" | jq -r '.[0].templateRef')
    # Same 63-byte hazard $run_name itself is guarded against above (see its own comment) —
    # appending -step0-<templateRef> isn't bounded by that truncation, so truncate the whole
    # composed name here too (entrypoint.sh/rgd-jobworkflow.yaml do the same for every other
    # step of a chain). Capped at 59, not 63: this is a JobRun CR name, and rgd-jobrun.yaml
    # prepends its own 4-byte "atm-" on top for the Job/Pod it creates, which also has to
    # fit in 63.
    step0_name="${run_name}-step0-${step0_template}"
    step0_name="${step0_name:0:59}"
    step0_name="${step0_name%-}"
    echo "$resolved_steps" | jq -c '.[0]' | jq --arg name "$step0_name" --arg run "$run_name" --arg owner "$job_owner" --arg ref "$git_ref" '
      {apiVersion: "REDACTED/v1alpha1", kind: "JobRun",
       metadata: {name: $name, labels: {"REDACTED/workflow-run": $run, "REDACTED/job-owner": $owner}},
       spec: {templateRef: .templateRef, args: (.args // {}), dryRun: (.dryRun // false),
              workflowRunRef: $run, stepIndex: 0, jobOwner: $owner, gitRef: $ref}}' | kubectl create --context core -f -

    local i job_name
    for i in $(seq 0 $((total_steps - 1))); do
        hsctl_log_info "waiting for workflow run $run_name step $i..."
        job_name=$(_run_wait_for_workflow_step "$run_name" "$i") || {
            hsctl_log_error "no Job appeared for workflow run $run_name step $i — check: kubectl get jobworkflowrun $run_name --context core -o yaml"
            exit 1
        }
        _run_stream_job "$job_name" "$namespace" || exit 1
    done
}

run_main() {
    local playbook="" cluster="" mode="remote" dry_run="false" playbook_set=false
    local chain_raw="" arg_kvs=() git_ref="main"

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --cluster) cluster="${2:-}"; [[ -z "$cluster" ]] && run_usage; shift 2 ;;
            --arg)
                [[ -z "${2:-}" || "${2:-}" != *=* ]] && run_usage
                arg_kvs+=("$2"); shift 2 ;;
            -e|--execution-mode)
                mode="${2:-}"
                [[ "$mode" != "local" && "$mode" != "remote" ]] && run_usage
                shift 2 ;;
            --dry-run) dry_run="true"; shift ;;
            --chain)
                chain_raw="${2:-}"; [[ -z "$chain_raw" ]] && run_usage
                shift 2 ;;
            --git-ref)
                git_ref="${2:-}"; [[ -z "$git_ref" ]] && run_usage
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
        command -v jq &>/dev/null || { echo "hsctl run: jq is required (brew install jq)" >&2; exit 1; }
        local cli_args_json="{}"
        if [[ ${#arg_kvs[@]} -gt 0 ]]; then
            cli_args_json=$(jq -n --args '
                $ARGS.positional | map(split("=") | {(.[0]): (.[1:] | join("="))}) | add // {}' \
                -- "${arg_kvs[@]}")
        fi
        [[ -n "$cluster" ]] && cli_args_json=$(jq --arg v "$cluster" '. + {cluster: $v}' <<<"$cli_args_json")
        _run_remote "$playbook" "$cli_args_json" "$dry_run" "$chain_raw" "$git_ref"
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
