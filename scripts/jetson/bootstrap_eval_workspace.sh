#!/usr/bin/env bash

set -euo pipefail

usage() {
  cat <<'EOF'
Usage:
  bootstrap_eval_workspace.sh [workspace_root]

Default workspace_root:
  ~/Documents/depth_validation_workspace

This script creates a standard folder layout on the Jetson and stores
an environment report to help reproduce Docker builds and model tests.
EOF
}

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  usage
  exit 0
fi

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
REPO_ROOT=$(cd "$SCRIPT_DIR/../.." && pwd)
WORKSPACE_ROOT=${1:-"$HOME/Documents/depth_validation_workspace"}

mkdir -p "$WORKSPACE_ROOT"/{artifacts,docker_logs,external_models,reports}
mkdir -p "$WORKSPACE_ROOT"/reports/{docker,metrics,tegrastats}

REPORT_PATH="$WORKSPACE_ROOT/reports/jetson_environment.txt"

{
  echo "workspace_root=$WORKSPACE_ROOT"
  echo "repo_root=$REPO_ROOT"
  echo "timestamp=$(date --iso-8601=seconds)"
  echo
  echo "## uname"
  uname -a
  echo
  echo "## hostnamectl"
  hostnamectl || true
  echo
  echo "## nv_tegra_release"
  cat /etc/nv_tegra_release 2>/dev/null || true
  echo
  echo "## jetpack packages"
  dpkg -l | grep -E 'nvidia-l4t-core|nvidia-jetpack' || true
  echo
  echo "## docker"
  docker --version || true
  docker compose version || true
  echo
  echo "## disk"
  df -h "$HOME" || true
} >"$REPORT_PATH"

cat <<EOF
Workspace initialized:
  $WORKSPACE_ROOT

Environment report:
  $REPORT_PATH
EOF
