#!/usr/bin/env bash
# Deletes JobRun/JobWorkflowRun CRs older than ARGS_JSON's "retentionDays" (default 7).
# The Jobs/Pods they created are already cleaned up on their own via
# ttlSecondsAfterFinished (see apps/automatron/templates/rgd-job{run,workflow}*.yaml) —
# this is just for the lightweight CR objects themselves, which kro doesn't otherwise
# expire on its own.
set -euo pipefail

retention_days=$(jq -r '.retentionDays // "7"' <<<"${ARGS_JSON:-{}}")
cutoff_epoch=$(date -u -d "-${retention_days} days" +%s)

for kind in jobrun jobworkflowrun; do
    kubectl get "$kind" -o json | jq -r --argjson cutoff "$cutoff_epoch" '
        .items[] | select((.metadata.creationTimestamp | fromdateiso8601) < $cutoff) | .metadata.name' \
    | while read -r name; do
        [[ -z "$name" ]] && continue
        echo "deleting $kind/$name (older than $retention_days days)"
        kubectl delete "$kind" "$name"
    done
done
