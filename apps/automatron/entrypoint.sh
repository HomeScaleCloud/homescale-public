#!/usr/bin/env bash
# Automatron entrypoint, runs inside the ansible-runner container. PLAYBOOK or
# SCRIPT_PATH (exactly one) selects what to run; CLUSTER/DRY_RUN are passed through.
# CHAIN_JOBS (optional) is a comma-separated list of JobTemplate names still to run, in
# order, after this one succeeds — on success, this creates a JobRun for the first name
# in the list (carrying the rest of the list as that JobRun's own spec.chain), the same
# mechanism a scheduled JobTemplate's spec.chain uses, and `hsctl run <name> --chain
# <name>[,<name>...] -e remote` uses for an ad hoc chain. CHAIN_ROOT threads a stable
# identity through every hop of one chain (see rgd-jobrun.yaml), used only to dedup
# against a still-active previous hop.
set -euo pipefail

REPO_DIR="${REPO_DIR:-/repo/current}"
PLAYBOOK="${PLAYBOOK:-}"
SCRIPT_PATH="${SCRIPT_PATH:-}"
SCRIPT_INTERPRETER="${SCRIPT_INTERPRETER:-bash}"
CLUSTER="${CLUSTER:-}"
DRY_RUN="${DRY_RUN:-false}"
CHAIN_JOBS="${CHAIN_JOBS:-}"
CHAIN_ROOT="${CHAIN_ROOT:-}"

if [[ -n "$PLAYBOOK" && -n "$SCRIPT_PATH" ]]; then
    echo "entrypoint: exactly one of PLAYBOOK / SCRIPT_PATH must be set, got both" >&2
    exit 1
elif [[ -z "$PLAYBOOK" && -z "$SCRIPT_PATH" ]]; then
    echo "entrypoint: exactly one of PLAYBOOK / SCRIPT_PATH must be set, got neither" >&2
    exit 1
fi

# infra/ansible/inventory/omni.py shells out to `hsctl get machines`, resolved
# from the git-cloned repo rather than baked into the image.
export HSCTL_REPO_ROOT="$REPO_DIR"
export PATH="$REPO_DIR:$PATH"

if [[ -n "$SCRIPT_PATH" ]]; then
    cd "$REPO_DIR"
    echo "running $SCRIPT_PATH (interpreter: $SCRIPT_INTERPRETER)${CLUSTER:+ (target: $CLUSTER)}"
    "$SCRIPT_INTERPRETER" "$SCRIPT_PATH" ${CLUSTER:+"$CLUSTER"}
else
    cd "$REPO_DIR/infra/ansible"

    ansible-galaxy collection install -r requirements.yml

    extra_args=(-e "dry_run=$DRY_RUN")
    case "$PLAYBOOK" in
        bootstrap-core)
            playbook_file=playbooks/bootstrap-core.yml
            extra_args+=(-e cluster_name=core)
            ;;
        bootstrap-cluster)
            playbook_file=playbooks/bootstrap-cluster.yml
            [[ -n "$CLUSTER" ]] && extra_args+=(-e "target=$CLUSTER")
            ;;
        *)
            playbook_file="playbooks/$PLAYBOOK.yml"
            [[ -n "$CLUSTER" ]] && extra_args+=(-e "target=$CLUSTER")
            ;;
    esac

    ansible-playbook "$playbook_file" "${extra_args[@]}"
fi

if [[ -n "$CHAIN_JOBS" && "$DRY_RUN" != "true" ]]; then
    namespace=$(cat /var/run/secrets/kubernetes.io/serviceaccount/namespace)
    next_template="${CHAIN_JOBS%%,*}"
    if [[ "$CHAIN_JOBS" == *,* ]]; then
        remaining="${CHAIN_JOBS#*,}"
    else
        remaining=""
    fi

    # concurrencyPolicy: Forbid doesn't cover Jobs created this way, so guard against a
    # slow prior hop targeting the same template still being active. Scoped by template,
    # not by chain root, since a scheduled JobTemplate's chain root differs on every
    # firing (it's the CronJob's own generated Job name) — this is what actually catches
    # one firing's chain still running when the next firing's chain tries to start it too.
    template_label="REDACTED/template=$next_template"
    active=$(kubectl get jobs -n "$namespace" -l "$template_label" \
        -o jsonpath='{range .items[?(@.status.active>0)]}{.metadata.name}{"\n"}{end}')
    if [[ -n "$active" ]]; then
        echo "a Job for template $next_template is already running ($active) — skipping chain hop"
    else
        run_name="${CHAIN_ROOT}-$(date +%s)"
        echo "chaining into $next_template (remaining: ${remaining:-none}) as JobRun $run_name"
        jq -n --arg name "$run_name" --arg template "$next_template" \
            --arg remaining "$remaining" --arg root "$CHAIN_ROOT" '
            {apiVersion: "REDACTED/v1alpha1", kind: "JobRun",
             metadata: {name: $name, labels: {"REDACTED/chain-root": $root}},
             spec: {templateRef: $template, chain: $remaining, chainRoot: $root}}' \
            | kubectl apply -f -
    fi
fi
