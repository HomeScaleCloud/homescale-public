#!/usr/bin/env bash
# Enforce the alert/runbook contract from CLAUDE.md:
#
#   Every PrometheusRule alert defined in this repo must have
#     - a runbook_url annotation of the form
#       https://REDACTED/runbooks/<slug>/
#     - a docs/runbooks/<slug>.md page
#     - a nav entry for that page in mkdocs.yml
#   and every docs/runbooks/*.md page must belong to an alert and appear in
#   the mkdocs.yml nav.
#
# Only alerts defined in this repo's own PrometheusRule templates are checked
# (apps/*/templates/*.yaml containing `kind: PrometheusRule`) — not the
# kube-prometheus-stack built-ins, which are annotated with dashboard_url in
# apps/metrics/app.yaml instead.
#
# Usage: .github/scripts/check-runbooks.sh

set -euo pipefail

repo_root="$(git rev-parse --show-toplevel)"
cd "$repo_root"

runbooks_dir="docs/runbooks"
mkdocs="mkdocs.yml"
url_prefix="https://REDACTED/runbooks/"

fail=0
err() { echo "FAIL: $*" >&2; fail=1; }

claimed_slugs=""   # space-delimited, space-padded list of slugs an alert claims
alert_count=0

rule_files="$(
    git ls-files 'apps/*/templates/*.yaml' \
        | while IFS= read -r f; do grep -lq '^kind: PrometheusRule$' "$f" && echo "$f"; done \
        || true
)"

if [[ -z "$rule_files" ]]; then
    err "found no PrometheusRule templates under apps/*/templates/"
fi

while IFS= read -r f; do
    [[ -n "$f" ]] || continue
    # Pair each `- alert: X` with the runbook_url in its block. These two line
    # kinds are always plain (no Helm templating), even where descriptions
    # aren't, so a raw scan is safe.
    while IFS=$'\t' read -r alert url; do
        [[ -n "$alert" ]] || continue
        alert_count=$((alert_count + 1))
        if [[ -z "$url" ]]; then
            err "$f: alert '$alert' has no runbook_url annotation"
            continue
        fi
        if [[ "$url" != "$url_prefix"*/ ]]; then
            err "$f: alert '$alert' runbook_url '$url' is not ${url_prefix}<slug>/"
            continue
        fi
        slug="${url#"$url_prefix"}"
        slug="${slug%/}"
        claimed_slugs="$claimed_slugs $slug "

        [[ -f "$runbooks_dir/$slug.md" ]] || err "$f: alert '$alert' -> missing $runbooks_dir/$slug.md"
        grep -q "runbooks/$slug.md" "$mkdocs" || err "$f: alert '$alert' -> $runbooks_dir/$slug.md not in $mkdocs nav"
    done < <(
        awk '
            match($0, /^[[:space:]]*-[[:space:]]*alert:[[:space:]]*/) {
                if (alert != "") printf "%s\t%s\n", alert, url
                alert = substr($0, RLENGTH + 1); url = ""; next
            }
            match($0, /^[[:space:]]*runbook_url:[[:space:]]*/) {
                u = substr($0, RLENGTH + 1); gsub(/["'"'"' ]/, "", u); url = u
            }
            END { if (alert != "") printf "%s\t%s\n", alert, url }
        ' "$f"
    )
done <<< "$rule_files"

# Every runbook page must be claimed by an alert.
shopt -s nullglob
for page in "$runbooks_dir"/*.md; do
    base="$(basename "$page" .md)"
    [[ "$base" == "index" ]] && continue
    [[ "$claimed_slugs" == *" $base "* ]] || err "$page: no alert references runbooks/$base/ — orphan runbook"
done

# Every runbook nav entry in mkdocs.yml must point at a real file.
while IFS= read -r ref; do
    [[ -f "docs/$ref" ]] || err "$mkdocs: nav entry '$ref' has no file at docs/$ref"
done < <(grep -oE 'runbooks/[a-z0-9-]+\.md' "$mkdocs" | sort -u)

if [[ "$fail" -ne 0 ]]; then
    echo "check-runbooks.sh: FAILED" >&2
    exit 1
fi
echo "check-runbooks.sh: OK ($alert_count alerts, all with runbook + nav entry)"
