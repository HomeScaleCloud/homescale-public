#!/usr/bin/env bash
# Automatron entrypoint, runs inside the ansible-runner container. PLAYBOOK/CLUSTER/
# DRY_RUN select what to run. CHAIN_NEXT_CRONJOB (optional) clones that CronJob's
# jobTemplate into a one-off Job on success, e.g. so bootstrap-cluster always runs
# after omni-sync without relying on schedule offsets.
set -euo pipefail

REPO_DIR="${REPO_DIR:-/repo/current}"
PLAYBOOK="${PLAYBOOK:?PLAYBOOK env var is required}"
CLUSTER="${CLUSTER:-}"
DRY_RUN="${DRY_RUN:-false}"

# infra/ansible/inventory/omni.py shells out to `hsctl get machines`, resolved
# from the git-cloned repo rather than baked into the image.
export HSCTL_REPO_ROOT="$REPO_DIR"
export PATH="$REPO_DIR:$PATH"

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

if [[ -n "${CHAIN_NEXT_CRONJOB:-}" && "$DRY_RUN" != "true" ]]; then
    namespace=$(cat /var/run/secrets/kubernetes.io/serviceaccount/namespace)
    # concurrencyPolicy: Forbid doesn't cover Jobs created this way, so guard
    # against a slow prior chained run still being active via this label instead.
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
