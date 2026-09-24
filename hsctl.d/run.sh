#!/usr/bin/env bash
# hsctl run — run an Ansible playbook from infra/ansible/playbooks/, either locally or
# remotely as a one-off Kubernetes Job on automatron (apps/automatron), the in-cluster
# runner deployed to mgmt that also runs bootstrap-cluster on a 5-minute schedule.
#
# `bootstrap-mgmt`/`bootstrap-cluster` are the built-in cluster bootstrap playbooks and get
# special handling below — see "Local secrets" — but any other playbook name under
# infra/ansible/playbooks/ works too, both locally and remotely; it's just run as-is with
# no local secrets handling (see below). A playbook is always named explicitly — there's no
# "run everything" shortcut, since that's an easy way to fire off more infra changes than
# you meant to.
#
# Local secrets: automatron authenticates to Infisical by reusing the k8s Infisical
# Operator's own identity (INFISICAL_OPERATOR_CLIENT_ID/SECRET), mounted into its pod as
# env vars — nothing a laptop run can reproduce. For bootstrap-mgmt/bootstrap-cluster, local
# runs instead pre-fetch the same secrets via the caller's own `infisical` CLI session
# (browser SSO, same as hsctl_bmc_creds in _lib.sh) and hand them to Ansible as
# hsctl_local_secrets, which bootstrap-mgmt.yml and the cluster-secrets role use in place
# of their own Infisical login when hsctl_local is set. automatron is unaffected — those
# tasks still run their normal universal_auth login there. A playbook outside this pair
# that needs Infisical locally must add its own hsctl_local-aware fallback the same way
# before `hsctl run` can help it — this module doesn't know its secret paths, so it just
# runs it and lets any Infisical lookup inside fail on its own.

_run_bootstrap_playbooks=(bootstrap-mgmt bootstrap-cluster)

run_usage() {
    echo "Usage: hsctl run <playbook> [--cluster <name>] [-e|--execution-mode local|remote] [--dry-run]"
    echo ""
    echo "<playbook> is any filename (without .yml) under infra/ansible/playbooks/, e.g.:"
    echo "  bootstrap-mgmt      bootstrap the mgmt-class cluster"
    echo "  bootstrap-cluster   bootstrap workload clusters (all, or one via --cluster)"
    echo "  omni-sync           sync every cluster template + machine class into Omni;"
    echo "                      on success, chains a bootstrap-cluster run (see CLAUDE.md)"
    echo ""
    echo "Options:"
    echo "  --cluster <name>            passed through as -e target=<name>; meaningful for"
    echo "                              bootstrap-cluster (its Omni cluster ID, e.g. boa1-prod)"
    echo "  -e, --execution-mode <mode> 'local' or 'remote' (default: remote). remote creates a"
    echo "                              one-off Job on automatron (in the mgmt cluster) and"
    echo "                              streams its logs; requires a Tailscale-reachable mgmt"
    echo "                              apiserver and team-infra-plat/team-sec-plat membership"
    echo "                              (no PIM needed). local runs ansible-playbook right here"
    echo "                              — still required for the very first mgmt bootstrap,"
    echo "                              before automatron exists to dispatch to."
    echo "  --dry-run                   passed through as -e dry_run=true; only omni-sync acts"
    echo "                              on it today (adds --dry-run to its omnictl calls, and"
    echo "                              skips chaining into bootstrap-cluster)"
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

# Run bootstrap-mgmt or bootstrap-cluster locally, pre-fetching the secrets they'd otherwise
# get via CI's OIDC login (see the module-level comment) and handing them to Ansible as
# hsctl_local_secrets.
_run_bootstrap_local() {
    local playbook="$1" cluster="$2" dry_run="$3"

    command -v infisical &>/dev/null || { echo "hsctl run: the infisical CLI is required (brew install infisical)" >&2; exit 1; }
    command -v jq &>/dev/null || { echo "hsctl run: jq is required (brew install jq)" >&2; exit 1; }

    [[ -n "$cluster" && "$playbook" == "bootstrap-mgmt" ]] && hsctl_log_info "--cluster is ignored for bootstrap-mgmt"

    hsctl_log_info "fetching secrets from Infisical via local CLI session"
    local argocd_secrets infisical_op_secrets mgmt_kubeconfig_secrets='{}'
    argocd_secrets=$(_run_infisical_secrets /k8s/argocd/deploy-key) || exit 1
    infisical_op_secrets=$(_run_infisical_secrets /k8s/infisical) || exit 1
    [[ "$playbook" == "bootstrap-mgmt" ]] && { mgmt_kubeconfig_secrets=$(_run_infisical_secrets /k8s/automatron) || exit 1; }

    local extra_vars_file
    extra_vars_file=$(mktemp)
    chmod 600 "$extra_vars_file"
    # shellcheck disable=SC2064 # extra_vars_file is fixed at trap-set time, not re-evaluated later
    trap "rm -f '$extra_vars_file'" EXIT

    jq -n \
        --argjson argocd "$argocd_secrets" \
        --argjson infisical_op "$infisical_op_secrets" \
        --argjson mgmt_kubeconfig "$mgmt_kubeconfig_secrets" \
        '{hsctl_local: true, hsctl_local_secrets: {argocd_deploy_key: $argocd, infisical_operator: $infisical_op, mgmt_kubeconfig: $mgmt_kubeconfig}}' \
        > "$extra_vars_file"

    (
        cd "$HSCTL_REPO_ROOT/infra/ansible" || exit 1

        case "$playbook" in
            bootstrap-mgmt)
                hsctl_log_action "running bootstrap-mgmt.yml"
                ansible-playbook playbooks/bootstrap-mgmt.yml -e cluster_name=mgmt -e "dry_run=$dry_run" --extra-vars "@$extra_vars_file"
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
    local playbook="$1" cluster="$2" dry_run="$3"
    local playbook_file="$HSCTL_REPO_ROOT/infra/ansible/playbooks/$playbook.yml"

    [[ -f "$playbook_file" ]] || { hsctl_log_error "no such playbook: infra/ansible/playbooks/$playbook.yml"; exit 1; }

    (
        cd "$HSCTL_REPO_ROOT/infra/ansible" || exit 1
        hsctl_log_action "running $playbook.yml${cluster:+ (target: $cluster)}"
        if [[ -n "$cluster" ]]; then
            ansible-playbook "playbooks/$playbook.yml" -e target="$cluster" -e "dry_run=$dry_run"
        else
            ansible-playbook "playbooks/$playbook.yml" -e "dry_run=$dry_run"
        fi
    )
}

_run_local() {
    local playbook="$1" cluster="$2" dry_run="$3"

    command -v ansible-playbook &>/dev/null || { echo "hsctl run: ansible-playbook is required (pip install ansible)" >&2; exit 1; }

    if [[ " ${_run_bootstrap_playbooks[*]} " == *" $playbook "* ]]; then
        _run_bootstrap_local "$playbook" "$cluster" "$dry_run"
    else
        _run_generic_local "$playbook" "$cluster" "$dry_run"
    fi
}

_run_remote() {
    local playbook="$1" cluster="$2" dry_run="$3"
    local namespace="automatron"
    local job_name="${playbook}-$(date +%s)"
    # Every built-in playbook has its own CronJob (bootstrap-cluster's is suspended —
    # see apps/automatron/templates/cronjob-bootstrap-cluster.yaml); anything else falls
    # back to cloning omni-sync's jobTemplate, which is just this same pod shape with a
    # different PLAYBOOK/CLUSTER override anyway.
    local cronjob="automatron-$playbook"
    case "$playbook" in
        bootstrap-mgmt|bootstrap-cluster|omni-sync) ;;
        *) cronjob="automatron-omni-sync" ;;
    esac

    command -v kubectl &>/dev/null || { echo "hsctl run: kubectl is required" >&2; exit 1; }
    command -v jq &>/dev/null || { echo "hsctl run: jq is required (brew install jq)" >&2; exit 1; }

    # A `mgmt` context already present (e.g. CI pre-seeded one from MGMT_KUBECONFIG, or
    # a previous interactive run) is reused as-is via explicit --context mgmt on every
    # kubectl call below — the default/current-context is never touched in this case.
    # Only the first-ever bootstrap (no mgmt context yet) needs the interactive OIDC
    # flow (hsctl get kubeconfig), which — as a side effect of that shared function —
    # switches current-context to mgmt; restore it immediately afterward rather than
    # leaving it switched for the duration of this run.
    if ! kubectl config get-contexts -o name 2>/dev/null | grep -qx mgmt; then
        local prev_ctx
        prev_ctx=$(kubectl config current-context 2>/dev/null || true)
        # shellcheck source=/dev/null
        source "$HSCTL_ROOT/hsctl.d/get.sh"
        hsctl_log_info "no mgmt context found — authenticating via OIDC"
        get_kubeconfig mgmt >/dev/null
        [[ -n "$prev_ctx" ]] && kubectl config use-context "$prev_ctx" >/dev/null 2>&1
    fi

    # Whatever CronJob we clone the jobTemplate from, always pin its PLAYBOOK/CLUSTER/
    # DRY_RUN to what was actually asked for, and only carry over CHAIN_NEXT_CRONJOB
    # (chaining into bootstrap-cluster on success) when the playbook being dispatched is
    # actually omni-sync — a generic/other playbook falling back to omni-sync's
    # jobTemplate as its clone source shouldn't inherit that side effect.
    hsctl_log_action "creating Job $job_name (playbook=$playbook${cluster:+, cluster=$cluster}${dry_run:+, dry_run=$dry_run}) on automatron"
    kubectl get cronjob "$cronjob" -n "$namespace" --context mgmt -o json | \
        jq --arg name "$job_name" --arg playbook "$playbook" --arg cluster "$cluster" --arg dry_run "$dry_run" '
          {
            apiVersion: "batch/v1",
            kind: "Job",
            metadata: {name: $name, namespace: .metadata.namespace},
            spec: (.spec.jobTemplate.spec | .template.spec.containers = [
              .template.spec.containers[] |
              if .name == "automatron" then
                .env = ((.env // []) | map(select(.name != "PLAYBOOK" and .name != "CLUSTER" and .name != "DRY_RUN" and .name != "CHAIN_NEXT_CRONJOB"))
                  + [{name: "PLAYBOOK", value: $playbook}, {name: "CLUSTER", value: $cluster}, {name: "DRY_RUN", value: $dry_run}]
                  + (if $playbook == "omni-sync" then [{name: "CHAIN_NEXT_CRONJOB", value: "automatron-bootstrap-cluster"}] else [] end))
              else . end
            ])
          }' | kubectl create -f - --context mgmt

    hsctl_log_info "waiting for the pod to appear..."
    local attempt pod=""
    for attempt in $(seq 1 30); do
        sleep 2
        pod=$(kubectl get pods -n "$namespace" --context mgmt -l "job-name=$job_name" \
            -o jsonpath='{.items[0].metadata.name}' 2>/dev/null) || true
        [[ -n "$pod" ]] && break
    done

    if [[ -z "$pod" ]]; then
        hsctl_log_error "pod never appeared — check: kubectl get pods -n $namespace --context mgmt -l job-name=$job_name"
        exit 1
    fi

    # The automatron container sits behind the git-key-prep/git-clone initContainers
    # — `kubectl logs -f` errors out immediately rather than waiting if called before
    # it's actually started, so poll until it is.
    hsctl_log_info "waiting for the automatron container to start..."
    local started=""
    for attempt in $(seq 1 60); do
        started=$(kubectl get pod "$pod" -n "$namespace" --context mgmt \
            -o jsonpath='{.status.containerStatuses[?(@.name=="automatron")].started}' 2>/dev/null) || true
        [[ "$started" == "true" ]] && break
        sleep 3
    done

    if [[ "$started" != "true" ]]; then
        hsctl_log_error "automatron container never started — check: kubectl describe pod $pod -n $namespace --context mgmt"
        exit 1
    fi

    # kubecolor (if the caller has it — an interactive-shell tool, not assumed on
    # PATH e.g. in CI) colorizes this the same way `kubectl logs` would look run
    # by hand; every other kubectl call above parses structured output (json/
    # jsonpath) and must stay plain, since injected ANSI codes there breaks
    # parsing rather than just being cosmetic.
    local log_cmd="kubectl"
    command -v kubecolor &>/dev/null && log_cmd="kubecolor"
    "$log_cmd" logs -f "$pod" -c automatron -n "$namespace" --context mgmt

    local status
    status=$(kubectl get job "$job_name" -n "$namespace" --context mgmt \
        -o jsonpath='{.status.succeeded}' 2>/dev/null) || true
    if [[ "$status" != "1" ]]; then
        hsctl_log_error "job $job_name did not succeed — check: kubectl describe job $job_name -n $namespace --context mgmt"
        exit 1
    fi
    hsctl_log_success "job $job_name completed"
}

run_main() {
    local playbook="" cluster="" mode="remote" dry_run="false" playbook_set=false

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --cluster) cluster="${2:-}"; [[ -z "$cluster" ]] && run_usage; shift 2 ;;
            -e|--execution-mode)
                mode="${2:-}"
                [[ "$mode" != "local" && "$mode" != "remote" ]] && run_usage
                shift 2 ;;
            --dry-run) dry_run="true"; shift ;;
            -h|--help) run_usage ;;
            --*) echo "hsctl run: unknown flag '$1'" >&2; run_usage ;;
            *)
                [[ "$playbook_set" == true ]] && { echo "hsctl run: unexpected argument '$1'" >&2; run_usage; }
                playbook="$1"; playbook_set=true; shift ;;
        esac
    done

    [[ -z "$playbook" ]] && { echo "hsctl run: a playbook name is required" >&2; run_usage; }

    if [[ "$mode" == "remote" ]]; then
        _run_remote "$playbook" "$cluster" "$dry_run"
    else
        _run_local "$playbook" "$cluster" "$dry_run"
    fi
}
