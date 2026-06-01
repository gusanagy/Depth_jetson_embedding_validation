#!/usr/bin/env bash

set -euo pipefail

usage() {
  cat <<'EOF'
Usage:
  run_igev_flops.sh [options]

Options:
  --workspace-root PATH   Default: ~/Documents/depth_validation_workspace
  --dataset-root PATH     Default: IGEV/IGEV-Stereo/uwstereo/images/val
  --ckpt PATH             Default: pretrained_models/sceneflow/sceneflow.pth
  --output-json PATH      Required output flops.json path
  --image IMAGE           Default: depth-jetson-stereo:thor-jp71
  --valid-iters N         Default: 32
  --mixed-precision       Enable model mixed precision.
EOF
}

WORKSPACE_ROOT="$HOME/Documents/depth_validation_workspace"
DATASET_ROOT=""
CKPT=""
OUTPUT_JSON=""
IMAGE="depth-jetson-stereo:thor-jp71"
VALID_ITERS=32
MIXED_PRECISION=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --workspace-root) WORKSPACE_ROOT=$2; shift 2 ;;
    --dataset-root) DATASET_ROOT=$2; shift 2 ;;
    --ckpt) CKPT=$2; shift 2 ;;
    --output-json) OUTPUT_JSON=$2; shift 2 ;;
    --image) IMAGE=$2; shift 2 ;;
    --valid-iters) VALID_ITERS=$2; shift 2 ;;
    --mixed-precision) MIXED_PRECISION=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *) usage; exit 1 ;;
  esac
done

if [[ -z "$OUTPUT_JSON" ]]; then
  echo "--output-json is required" >&2
  exit 1
fi

MODEL_ROOT="$WORKSPACE_ROOT/external_models/IGEV/IGEV-Stereo"
CACHE_ROOT="$WORKSPACE_ROOT/cache/igev"

if [[ -z "$DATASET_ROOT" ]]; then
  DATASET_ROOT="$MODEL_ROOT/uwstereo/images/val"
fi
LEFT_DIR="$DATASET_ROOT/left"
RIGHT_DIR="$DATASET_ROOT/right"

if [[ -z "$CKPT" ]]; then
  CKPT="$MODEL_ROOT/pretrained_models/sceneflow/sceneflow.pth"
fi

if sudo -n docker info >/dev/null 2>&1; then
  DOCKER=(sudo -n docker)
else
  DOCKER=(docker)
fi

if [[ "$CKPT" == "$MODEL_ROOT"* ]]; then
  CONTAINER_CKPT="/workspace/model/${CKPT#$MODEL_ROOT/}"
else
  echo "Checkpoint must be inside $MODEL_ROOT for the current runner." >&2
  exit 1
fi

mkdir -p "$(dirname "$OUTPUT_JSON")" "$CACHE_ROOT/huggingface" "$CACHE_ROOT/torch"

mp_arg=()
if [[ $MIXED_PRECISION -eq 1 ]]; then
  mp_arg+=(--mixed-precision)
fi

"${DOCKER[@]}" run --rm --runtime=nvidia \
  --ipc=host \
  --ulimit memlock=-1 \
  --ulimit stack=67108864 \
  -v "$MODEL_ROOT":/workspace/model \
  -v "$DATASET_ROOT":/workspace/data:ro \
  -v "$(dirname "$OUTPUT_JSON")":/workspace/output \
  -v "$WORKSPACE_ROOT/depth_compare_sorriso":/workspace/runner:ro \
  -v "$CACHE_ROOT/huggingface":/workspace/cache/huggingface \
  -v "$CACHE_ROOT/torch":/workspace/cache/torch \
  "$IMAGE" \
  bash -lc "cd /workspace/model && export HF_HOME=/workspace/cache/huggingface TORCH_HOME=/workspace/cache/torch PYTHONPATH=/workspace/model:/workspace/model/core:\$PYTHONPATH && python3 /workspace/runner/scripts/jetson/igev_flops_probe.py --model-root /workspace/model --left-dir /workspace/data/left --right-dir /workspace/data/right --output-json /workspace/output/$(basename "$OUTPUT_JSON") --ckpt \"$CONTAINER_CKPT\" --valid-iters \"$VALID_ITERS\" ${mp_arg[*]}"
