#!/usr/bin/env bash

set -euo pipefail

WORKSPACE_ROOT=${1:-"$HOME/Documents/depth_validation_workspace"}
SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)

bash "$SCRIPT_DIR/run_depth_anything_v2.sh" --workspace-root "$WORKSPACE_ROOT" --encoder vitb
bash "$SCRIPT_DIR/run_foundation_stereo.sh" --workspace-root "$WORKSPACE_ROOT"
