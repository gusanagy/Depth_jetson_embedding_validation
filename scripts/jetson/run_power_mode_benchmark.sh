#!/usr/bin/env bash

set -euo pipefail

usage() {
  cat <<'EOF'
Usage:
  run_power_mode_benchmark.sh [options] -- <command> [args...]

Options:
  --workspace-root PATH   Default: ~/Documents/depth_validation_workspace
  --modes LIST            Comma-separated mode ids or names. Default: all
  --label NAME            Report label. Default: benchmark
  --cooldown-sec N        Delay after each mode switch. Default: 5
EOF
}

WORKSPACE_ROOT="$HOME/Documents/depth_validation_workspace"
MODES="all"
LABEL="benchmark"
COOLDOWN_SEC=5

while [[ $# -gt 0 ]]; do
  case "$1" in
    --workspace-root) WORKSPACE_ROOT=$2; shift 2 ;;
    --modes) MODES=$2; shift 2 ;;
    --label) LABEL=$2; shift 2 ;;
    --cooldown-sec) COOLDOWN_SEC=$2; shift 2 ;;
    --) shift; break ;;
    *) usage; exit 1 ;;
  esac
done

if [[ $# -eq 0 ]]; then
  usage
  exit 1
fi

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
bash "$SCRIPT_DIR/prepare_power_mode_plan.sh" \
  --workspace-root "$WORKSPACE_ROOT" \
  --label "$LABEL" \
  --modes "$MODES" \
  --overwrite -- "$@"

bash "$SCRIPT_DIR/resume_power_mode_plan.sh" \
  --workspace-root "$WORKSPACE_ROOT" \
  --label "$LABEL" \
  --cooldown-sec "$COOLDOWN_SEC"
