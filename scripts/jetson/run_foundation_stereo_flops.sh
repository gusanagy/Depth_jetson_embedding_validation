#!/usr/bin/env bash

set -euo pipefail

usage() {
  cat <<'EOF'
Usage:
  run_foundation_stereo_flops.sh [options]

Options:
  --workspace-root PATH   Default: ~/Documents/depth_validation_workspace
  --dataset-root PATH     Optional stereo dataset root
  --ckpt PATH             Optional checkpoint path
  --output-json PATH      Required output flops.json path
  --image IMAGE           Default: depth-jetson-stereo:thor-jp71
  --valid-iters N         Default: 32
EOF
}

WORKSPACE_ROOT="$HOME/Documents/depth_validation_workspace"
DATASET_ROOT=""
CKPT=""
OUTPUT_JSON=""
IMAGE="depth-jetson-stereo:thor-jp71"
VALID_ITERS=32

while [[ $# -gt 0 ]]; do
  case "$1" in
    --workspace-root) WORKSPACE_ROOT=$2; shift 2 ;;
    --dataset-root) DATASET_ROOT=$2; shift 2 ;;
    --ckpt) CKPT=$2; shift 2 ;;
    --output-json) OUTPUT_JSON=$2; shift 2 ;;
    --image) IMAGE=$2; shift 2 ;;
    --valid-iters) VALID_ITERS=$2; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) usage; exit 1 ;;
  esac
done

if [[ -z "$OUTPUT_JSON" ]]; then
  echo "--output-json is required" >&2
  exit 1
fi

MODEL_ROOT="$WORKSPACE_ROOT/external_models/FoundationStereo"
if [[ -z "$DATASET_ROOT" ]]; then
  if [[ -d "$MODEL_ROOT/datasets/uwstereo/images/val" ]]; then
    DATASET_ROOT="$MODEL_ROOT/datasets/uwstereo/images/val"
  else
    DATASET_ROOT="$WORKSPACE_ROOT/external_models/IGEV/IGEV-Stereo/uwstereo/images/val"
  fi
fi
if [[ -z "$CKPT" ]]; then
  CKPT="$MODEL_ROOT/pretrained_models/vit-large/model_large_bp2.pth"
fi

if [[ "$CKPT" == "$MODEL_ROOT"* ]]; then
  CONTAINER_CKPT="/workspace/model/${CKPT#$MODEL_ROOT/}"
else
  echo "Checkpoint must be inside $MODEL_ROOT for the current runner." >&2
  exit 1
fi

if sudo -n docker info >/dev/null 2>&1; then
  DOCKER=(sudo -n docker)
else
  DOCKER=(docker)
fi

mkdir -p "$(dirname "$OUTPUT_JSON")"
OUTPUT_BASENAME=$(basename "$OUTPUT_JSON")

"${DOCKER[@]}" run --rm --runtime=nvidia \
  --ipc=host \
  --ulimit memlock=-1 \
  --ulimit stack=67108864 \
  -v "$MODEL_ROOT":/workspace/model \
  -v "$DATASET_ROOT":/workspace/data:ro \
  -v "$(dirname "$OUTPUT_JSON")":/workspace/output \
  -v "$WORKSPACE_ROOT/depth_compare_sorriso":/workspace/runner:ro \
  "$IMAGE" \
  bash -lc "cd /workspace/model && python3 /workspace/runner/scripts/jetson/foundation_stereo_flops_probe.py --model-root /workspace/model --dataset-root /workspace/data --ckpt \"$CONTAINER_CKPT\" --output-json /workspace/output/$OUTPUT_BASENAME --valid-iters \"$VALID_ITERS\""
