#!/usr/bin/env bash
# Automatron entrypoint — runs inside the ansible-runner container. The repo is
# git-cloned into REPO_DIR (default /repo/current) by the git-clone initContainer
# before this starts. PLAYBOOK/CLUSTER/DRY_RUN select what to run, same dispatch
# shape as hsctl run's local execution mode (hsctl.d/run.sh).
#
# CHAIN_NEXT_CRONJOB (optional): on success, clone that CronJob's jobTemplate into
# a one-off, normally-timestamped Job in this pod's own namespace, using kubectl's
# in-cluster auth (this pod's own ServiceAccount — see apps/rbac's job-operator
# binding for automatron). Used so bootstrap-cluster's CronJob always runs after
# omni-sync's, without relying on schedule offsets: omni-sync chains it,
# bootstrap-cluster's own CronJob stays suspended (its jobTemplate is only ever
# cloned, never auto-fired).
set -euo pipefail

REPO_DIR="${REPO_DIR:-/repo/current}"
PLAYBOOK="${PLAYBOOK:?PLAYBOOK env var is required}"
CLUSTER="${CLUSTER:-}"
DRY_RUN="${DRY_RUN:-false}"

# infra/ansible/inventory/omni.py shells out to `hsctl get machines`, which lives
# in the git-cloned repo itself (not baked into the image) — same binary hsctl
# run's local mode uses, just resolved from here instead of $HOME/Repos/homescale.
export HSCTL_REPO_ROOT="$REPO_DIR"
export PATH="$REPO_DIR:$PATH"

cd "$REPO_DIR/infra/ansible"

ansible-galaxy collection install -r requirements.yml

extra_args=(-e "dry_run=$DRY_RUN")
case "$PLAYBOOK" in
    bootstrap-mgmt)
        playbook_file=playbooks/bootstrap-mgmt.yml
        extra_args+=(-e cluster_name=mgmt)
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

if [[ -n "${CHAIN_NEXT_CRONJOB:-}" && "$DRY_RUN" != "true" ]]; then
    namespace=$(cat /var/run/secrets/kubernetes.io/serviceaccount/namespace)
    # Timestamped name, matching every other Job in this app (CronJob-fired and
    # hsctl's ad hoc ones) so `kubectl get jobs` shows what it's actually running.
    # concurrencyPolicy: Forbid only throttles CronJob-scheduled Jobs, not ones
    # created this way, so a slow bootstrap-cluster run could still be going when
    # the next omni-sync cycle tries to chain another one — guarded against below
    # via a label instead of the old fixed-name/AlreadyExists trick.
    chain_label="REDACTED/chained-from=$CHAIN_NEXT_CRONJOB"
    active=$(kubectl get jobs -n "$namespace" -l "$chain_label" \
        -o jsonpath='{range .items[?(@.status.active>0)]}{.metadata.name}{"\n"}{end}')
    if [[ -n "$active" ]]; then
        echo "a chained Job is already running ($active) — skipping"
    else
        chain_job="${CHAIN_NEXT_CRONJOB}-$(date +%s)"
        echo "chaining into $CHAIN_NEXT_CRONJOB as Job $chain_job"
        manifest=$(kubectl get cronjob "$CHAIN_NEXT_CRONJOB" -n "$namespace" -o json | \
            jq --arg name "$chain_job" --arg src "$CHAIN_NEXT_CRONJOB" \
               '{apiVersion: "batch/v1", kind: "Job", metadata: {name: $name, namespace: .metadata.namespace, labels: {"REDACTED/chained-from": $src}}, spec: (.spec.jobTemplate.spec + {ttlSecondsAfterFinished: 300})}')
        echo "$manifest" | kubectl create -f -
    fi
fi
