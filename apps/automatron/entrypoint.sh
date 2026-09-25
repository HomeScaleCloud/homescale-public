#!/usr/bin/env bash
# Automatron entrypoint, runs inside the ansible-runner container. PLAYBOOK or
# SCRIPT_PATH (exactly one) selects what to run; DRY_RUN is passed through. ARGS_JSON is
# a JSON object of free-form extra-vars/script arguments (already fully resolved — see
# rgd-jobrun.yaml's map.merge() with the JobTemplate's own defaultArgs, and CLAUDE.md's
# Automatron section for the full precedence rule) — passed to ansible as extra-vars
# wholesale, so any playbook can use any key, and exported as-is for scripts to parse
# themselves. `cluster` is not a first-class concept here, just a commonly-used arg key —
# see below for the one place it still gets special-cased (translating to ansible's own
# `target` variable, for bootstrap-cluster and generic playbooks).
# WORKFLOW_RUN_NAME/STEP_INDEX (both optional) mean this run is one step of a
# JobWorkflowRun — on success, it reads spec.steps[STEP_INDEX+1] off that JobWorkflowRun
# (already fully resolved — no further precedence/override logic needed here, see
# rgd-jobworkflowrun.yaml) and, if present, creates a JobRun for it, named
# <run>-step<N>-<templateRef> so the Job/Pod it produces is always identifiable by which
# JobTemplate it's actually running, not just a step number. Same mechanism the
# JobWorkflow RGD's kickoff container uses for step 0 of a scheduled run, and
# `hsctl run <workflow-or-template> [--chain ...] -e remote` uses for step 0 of an ad
# hoc run. JOB_OWNER and GIT_REF (both set once, at the start of a chain — see
# hsctl.d/run.sh and rgd-jobworkflow.yaml's kickoff container) are threaded through
# unchanged to every subsequent step, so the whole chain keeps one consistent owner and
# every step checks out the same ref (see rgd-jobrun.yaml's spec.gitRef).
set -euo pipefail

REPO_DIR="${REPO_DIR:-/repo/current}"
PLAYBOOK="${PLAYBOOK:-}"
SCRIPT_PATH="${SCRIPT_PATH:-}"
SCRIPT_INTERPRETER="${SCRIPT_INTERPRETER:-bash}"
# NOT `ARGS_JSON="${ARGS_JSON:-{}}"` — bash's scanner for a ${VAR:-word} default
# misjudges where the substitution ends when word contains a literal `{}`, so it silently
# appends a stray trailing `}` even when ARGS_JSON is already set to a real value (e.g.
# `{"cluster":"x"}` becomes `{"cluster":"x"}}`), breaking every jq call downstream —
# confirmed live, this broke every run.
[[ -z "${ARGS_JSON:-}" ]] && ARGS_JSON="{}"
DRY_RUN="${DRY_RUN:-false}"
WORKFLOW_RUN_NAME="${WORKFLOW_RUN_NAME:-}"
STEP_INDEX="${STEP_INDEX:--1}"
JOB_OWNER="${JOB_OWNER:-}"
GIT_REF="${GIT_REF:-main}"
CLUSTER=$(jq -r '.cluster // ""' <<<"$ARGS_JSON")

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
    # SCRIPT_PATH is a bare filename under infra/automatron/scripts/ (same convention as
    # PLAYBOOK being a bare name under infra/ansible/playbooks/ below), joined back onto
    # that directory here rather than carrying the full repo path in the CR — keeps the
    # JobTemplate/JobRun printer columns readable.
    script_file="infra/automatron/scripts/$SCRIPT_PATH"
    echo "running $script_file (interpreter: $SCRIPT_INTERPRETER, args: $ARGS_JSON)"
    export ARGS_JSON
    "$SCRIPT_INTERPRETER" "$script_file"
else
    cd "$REPO_DIR/infra/ansible"

    ansible-galaxy collection install -r requirements.yml

    # ARGS_JSON is passed wholesale as extra-vars, so any playbook can use any key
    # directly; bootstrap-core/bootstrap-cluster and (for backwards compatibility) any
    # other playbook additionally get `cluster` translated to ansible's own `target`
    # variable, which is what they've always actually expected.
    extra_args=(-e "dry_run=$DRY_RUN" -e "$ARGS_JSON")
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

if [[ -n "$WORKFLOW_RUN_NAME" && "$DRY_RUN" != "true" ]]; then
    namespace=$(cat /var/run/secrets/kubernetes.io/serviceaccount/namespace)
    next_index=$((STEP_INDEX + 1))
    next_step=$(kubectl get jobworkflowrun "$WORKFLOW_RUN_NAME" -o json | \
        jq -c ".spec.steps[$next_index] // empty")

    if [[ -z "$next_step" ]]; then
        echo "workflow run $WORKFLOW_RUN_NAME: no step $next_index — done"
    else
        next_template=$(jq -r '.templateRef' <<<"$next_step")
        # WORKFLOW_RUN_NAME is already bounded to stay well under 63 bytes on its own (see
        # hsctl.d/run.sh's _run_truncate / rgd-jobworkflow.yaml's truncate16), but appending
        # -step<N>-<templateRef> on top of that isn't — confirmed live: kro's dynamic
        # controller permanently fails to reconcile a JobWorkflowRun whose own name (reused
        # as this JobRun's workflow-run label value) exceeds 63 bytes, requeuing forever with
        # no way to recover short of deleting the object, since names are immutable. Truncate
        # the whole composed name, not just its parts, so this holds regardless of which
        # component ends up long. Capped at 59, not 63: run_name is this JobRun CR's own
        # name (deliberately unprefixed — see hsctl.d/run.sh), and rgd-jobrun.yaml prepends
        # its own 4-byte "atm-" on top for the Job/Pod it creates, which also has to fit
        # in 63.
        run_name="${WORKFLOW_RUN_NAME}-step${next_index}-${next_template}"
        run_name="${run_name:0:59}"
        run_name="${run_name%-}"

        # concurrencyPolicy: Forbid doesn't cover Jobs created this way, so guard against
        # double-creating this exact next step (e.g. this script somehow running twice) by
        # checking for a Job with its exact, deterministic name — NOT "any Job in this run
        # is active", which always matches the current step's own still-running Job (this
        # script executes inside it, before it's exited) and would skip every single time.
        # The Job itself is named "atm-$run_name", not "$run_name" (see rgd-jobrun.yaml).
        job_name="atm-${run_name}"
        active=$(kubectl get job "$job_name" -n "$namespace" -o jsonpath='{.status.active}' 2>/dev/null) || true
        if [[ "$active" == "1" ]]; then
            echo "Job $job_name already exists and is active — skipping"
        else
            echo "continuing workflow run $WORKFLOW_RUN_NAME: step $next_index ($next_template) as JobRun $run_name"
            echo "$next_step" | jq --arg name "$run_name" --arg run "$WORKFLOW_RUN_NAME" --arg idx "$next_index" --arg owner "$JOB_OWNER" --arg ref "$GIT_REF" '
                {apiVersion: "REDACTED/v1alpha1", kind: "JobRun",
                 metadata: {name: $name, labels: {"REDACTED/workflow-run": $run, "REDACTED/job-owner": $owner}},
                 spec: {templateRef: .templateRef, args: (.args // {}), dryRun: (.dryRun // false),
                        workflowRunRef: $run, stepIndex: ($idx | tonumber), jobOwner: $owner, gitRef: $ref}}' \
                | kubectl apply -f -
        fi
    fi
fi
