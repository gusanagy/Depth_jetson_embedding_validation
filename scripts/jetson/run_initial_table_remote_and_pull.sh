#!/usr/bin/env bash

set -euo pipefail

usage() {
  cat <<'EOF'
Usage:
  run_initial_table_remote_and_pull.sh [options]

Runs the initial-table pipeline on the Jetson, finalizes the report there,
and pulls the resulting report folder back to this local machine.

Options:
  --label NAME                 Required report label.
  --profile NAME              quick or full. Default: full
  --remote-host HOST          Default: PDI@10.230.88.175
  --remote-workspace PATH     Default: ~/Documents/depth_validation_workspace
  --remote-repo PATH          Default: <remote-workspace>/depth_compare_sorriso
  --local-repo PATH           Default: current repo root
  --title TEXT                Optional PNG title override.
  --caption TEXT              Optional LaTeX caption override.
  --latex-label TEXT          Optional LaTeX label override.
  --skip-run                  Only finalize and pull an existing remote report.
EOF
}

LABEL=""
PROFILE="full"
REMOTE_HOST="PDI@10.230.88.175"
REMOTE_WORKSPACE='~/Documents/depth_validation_workspace'
REMOTE_REPO=""
LOCAL_REPO=""
TITLE=""
CAPTION=""
LATEX_LABEL=""
SKIP_RUN=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --label) LABEL=$2; shift 2 ;;
    --profile) PROFILE=$2; shift 2 ;;
    --remote-host) REMOTE_HOST=$2; shift 2 ;;
    --remote-workspace) REMOTE_WORKSPACE=$2; shift 2 ;;
    --remote-repo) REMOTE_REPO=$2; shift 2 ;;
    --local-repo) LOCAL_REPO=$2; shift 2 ;;
    --title) TITLE=$2; shift 2 ;;
    --caption) CAPTION=$2; shift 2 ;;
    --latex-label) LATEX_LABEL=$2; shift 2 ;;
    --skip-run) SKIP_RUN=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *) usage; exit 1 ;;
  esac
done

if [[ -z "$LABEL" ]]; then
  echo "--label is required" >&2
  exit 1
fi

if [[ "$PROFILE" != "quick" && "$PROFILE" != "full" ]]; then
  echo "Invalid --profile: $PROFILE" >&2
  exit 1
fi

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
REPO_ROOT=$(cd "$SCRIPT_DIR/../.." && pwd)
LOCAL_REPO=${LOCAL_REPO:-$REPO_ROOT}
REMOTE_REPO=${REMOTE_REPO:-$REMOTE_WORKSPACE/depth_compare_sorriso}
LOCAL_REPORTS_DIR="$LOCAL_REPO/reports/initial_table"
LOCAL_TARGET_DIR="$LOCAL_REPORTS_DIR/$LABEL"

mkdir -p "$LOCAL_REPORTS_DIR"

remote_cmd="cd $REMOTE_REPO && git pull --ff-only origin main"

if [[ $SKIP_RUN -eq 0 ]]; then
  remote_cmd="$remote_cmd && bash scripts/jetson/run_initial_table_current_mode.sh --workspace-root $REMOTE_WORKSPACE --label $LABEL --profile $PROFILE"
fi

remote_cmd="$remote_cmd && bash scripts/jetson/finalize_initial_table_report.sh --workspace-root $REMOTE_WORKSPACE --label $LABEL"

if [[ -n "$TITLE" ]]; then
  remote_cmd="$remote_cmd --title \"$TITLE\""
fi
if [[ -n "$CAPTION" ]]; then
  remote_cmd="$remote_cmd --caption \"$CAPTION\""
fi
if [[ -n "$LATEX_LABEL" ]]; then
  remote_cmd="$remote_cmd --latex-label \"$LATEX_LABEL\""
fi

ssh -o StrictHostKeyChecking=no "$REMOTE_HOST" "$remote_cmd"

tmp_parent=$(mktemp -d "$LOCAL_REPORTS_DIR/.pull_${LABEL}_XXXXXX")
scp -o StrictHostKeyChecking=no -r \
  "$REMOTE_HOST:$REMOTE_WORKSPACE/reports/initial_table/$LABEL" \
  "$tmp_parent/"

if [[ -d "$LOCAL_TARGET_DIR" ]]; then
  mv "$LOCAL_TARGET_DIR" "$LOCAL_TARGET_DIR.bak.$(date +%Y%m%d_%H%M%S)"
fi

mv "$tmp_parent/$LABEL" "$LOCAL_TARGET_DIR"
rmdir "$tmp_parent"

echo "Local report root: $LOCAL_TARGET_DIR"
echo "CSV: $LOCAL_TARGET_DIR/summary_enriched.csv"
echo "PNG: $LOCAL_TARGET_DIR/${LABEL}_plot.png"
echo "LaTeX: $LOCAL_TARGET_DIR/table_publication.tex"
