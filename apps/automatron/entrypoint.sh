#!/usr/bin/env bash
# Automatron entrypoint, runs inside the ansible-runner container. PLAYBOOK or
# SCRIPT_PATH (exactly one) selects what to run; CLUSTER/DRY_RUN are passed through.
# WORKFLOW_NAME/WORKFLOW_RUN_NAME/WORKFLOW_STEP_INDEX (all optional) mean this run is one
# step of a JobWorkflowRun — on success, the next step (if any) is chained by applying a
# JobRun CR labeled with the same WORKFLOW_RUN_NAME (so JobWorkflowRun's status can find
# it), same mechanism the JobWorkflow RGD's kickoff container uses for step 0 (see
# rgd-jobworkflow.yaml) and `hsctl run <workflow> -e remote` uses for an ad hoc run.
set -euo pipefail

REPO_DIR="${REPO_DIR:-/repo/current}"
PLAYBOOK="${PLAYBOOK:-}"
SCRIPT_PATH="${SCRIPT_PATH:-}"
SCRIPT_INTERPRETER="${SCRIPT_INTERPRETER:-bash}"
CLUSTER="${CLUSTER:-}"
DRY_RUN="${DRY_RUN:-false}"
WORKFLOW_NAME="${WORKFLOW_NAME:-}"
WORKFLOW_RUN_NAME="${WORKFLOW_RUN_NAME:-}"
WORKFLOW_STEP_INDEX="${WORKFLOW_STEP_INDEX:--1}"

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

if [[ -n "$WORKFLOW_NAME" && "$DRY_RUN" != "true" ]]; then
    # JobWorkflow/JobRun are cluster-scoped (no -n needed); the native Job dedup check
    # below still needs one, since batch/v1 Job has no cluster-scoped form.
    namespace=$(cat /var/run/secrets/kubernetes.io/serviceaccount/namespace)
    next_index=$((WORKFLOW_STEP_INDEX + 1))
    next_step=$(kubectl get jobworkflow "$WORKFLOW_NAME" -o json | \
        jq -c ".spec.steps[$next_index] // empty")

    if [[ -z "$next_step" ]]; then
        echo "workflow $WORKFLOW_NAME (run $WORKFLOW_RUN_NAME): no step $next_index — done"
    else
        # concurrencyPolicy: Forbid doesn't cover Jobs created this way, so guard against a
        # slow prior chained run of *this run* still being active via this label instead
        # (workflow-run, not workflow — a different run of the same workflow may legitimately
        # be in flight concurrently, e.g. an ad hoc run overlapping the scheduled one).
        run_label="REDACTED/workflow-run=$WORKFLOW_RUN_NAME"
        active=$(kubectl get jobs -n "$namespace" -l "$run_label" \
            -o jsonpath='{range .items[?(@.status.active>0)]}{.metadata.name}{"\n"}{end}')
        if [[ -n "$active" ]]; then
            echo "a chained Job for workflow run $WORKFLOW_RUN_NAME is already running ($active) — skipping"
        else
            run_name="${WORKFLOW_RUN_NAME}-step${next_index}"
            echo "chaining into $WORKFLOW_NAME run $WORKFLOW_RUN_NAME step $next_index as JobRun $run_name"
            echo "$next_step" | jq --arg name "$run_name" --arg wf "$WORKFLOW_NAME" \
                --arg run "$WORKFLOW_RUN_NAME" --arg idx "$next_index" '
                {apiVersion: "REDACTED/v1alpha1", kind: "JobRun",
                 metadata: {name: $name, labels: {"REDACTED/workflow": $wf, "REDACTED/workflow-run": $run}},
                 spec: {templateRef: .templateRef, cluster: (.cluster // ""), dryRun: (.dryRun // false),
                        workflowRef: $wf, workflowRunRef: $run, workflowStepIndex: ($idx | tonumber)}}' \
                | kubectl apply -f -
        fi
    fi
fi
