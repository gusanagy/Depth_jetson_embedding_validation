#!/usr/bin/env bash

set -euo pipefail

usage() {
  cat <<'EOF'
Usage:
  run_igev.sh [options]

Options:
  --workspace-root PATH   Default: ~/Documents/depth_validation_workspace
  --dataset-root PATH     Override stereo validation root. Default:
                          IGEV/IGEV-Stereo/uwstereo/images/val
  --ckpt PATH             Default:
                          IGEV/IGEV-Stereo/pretrained_models/sceneflow/sceneflow.pth
  --limit N               Optional pair limit.
  --image IMAGE           Docker image tag. Default: depth-jetson-stereo:thor-jp71
  --mixed-precision       Enable model mixed precision.
  --no-progress           Disable tqdm progress bar.
EOF
}

WORKSPACE_ROOT="$HOME/Documents/depth_validation_workspace"
DATASET_ROOT=""
CKPT=""
LIMIT=0
IMAGE="depth-jetson-stereo:thor-jp71"
MIXED_PRECISION=0
SHOW_PROGRESS=1

while [[ $# -gt 0 ]]; do
  case "$1" in
    --workspace-root) WORKSPACE_ROOT=$2; shift 2 ;;
    --dataset-root) DATASET_ROOT=$2; shift 2 ;;
    --ckpt) CKPT=$2; shift 2 ;;
    --limit) LIMIT=$2; shift 2 ;;
    --image) IMAGE=$2; shift 2 ;;
    --mixed-precision) MIXED_PRECISION=1; shift ;;
    --no-progress) SHOW_PROGRESS=0; shift ;;
    -h|--help) usage; exit 0 ;;
    *) usage; exit 1 ;;
  esac
done

MODEL_ROOT="$WORKSPACE_ROOT/external_models/IGEV/IGEV-Stereo"
OUTPUT_ROOT="$WORKSPACE_ROOT/artifacts/igev/val"

if [[ -z "$DATASET_ROOT" ]]; then
  DATASET_ROOT="$MODEL_ROOT/uwstereo/images/val"
fi
LEFT_DIR="$DATASET_ROOT/left"
RIGHT_DIR="$DATASET_ROOT/right"

if [[ -z "$CKPT" ]]; then
  CKPT="$MODEL_ROOT/pretrained_models/sceneflow/sceneflow.pth"
fi

if [[ ! -d "$LEFT_DIR" || ! -d "$RIGHT_DIR" ]]; then
  echo "Stereo validation directories not found under: $DATASET_ROOT" >&2
  exit 1
fi

if [[ ! -f "$CKPT" ]]; then
  echo "Checkpoint not found: $CKPT" >&2
  exit 1
fi

if sudo -n docker info >/dev/null 2>&1; then
  DOCKER=(sudo -n docker)
else
  DOCKER=(docker)
fi

if ! "${DOCKER[@]}" image inspect "$IMAGE" >/dev/null 2>&1; then
  echo "Docker image not found: $IMAGE" >&2
  echo "Build it with: bash scripts/jetson/build_docker_images.sh --only stereo" >&2
  exit 1
fi

if [[ "$CKPT" == "$MODEL_ROOT"* ]]; then
  CONTAINER_CKPT="/workspace/model/${CKPT#$MODEL_ROOT/}"
else
  echo "Checkpoint must be inside $MODEL_ROOT for the current runner." >&2
  exit 1
fi

mkdir -p "$OUTPUT_ROOT"

progress_arg=()
if [[ $SHOW_PROGRESS -eq 0 ]]; then
  progress_arg+=(--no-progress)
fi

limit_arg=()
if [[ "$LIMIT" -gt 0 ]]; then
  limit_arg+=(--limit "$LIMIT")
fi

mp_arg=()
if [[ $MIXED_PRECISION -eq 1 ]]; then
  mp_arg+=(--mixed-precision)
fi

echo
echo "== IGEV stereo val limit=$LIMIT =="
"${DOCKER[@]}" run --rm --runtime=nvidia \
  -v "$MODEL_ROOT":/workspace/model \
  -v "$DATASET_ROOT":/workspace/data:ro \
  -v "$OUTPUT_ROOT":/workspace/output \
  -v "$WORKSPACE_ROOT/depth_compare_sorriso":/workspace/runner:ro \
  "$IMAGE" \
  bash -lc "cd /workspace/model && PYTHONPATH=/workspace/model:/workspace/model/core:\$PYTHONPATH python3 /workspace/runner/scripts/jetson/igev_batch.py --model-root /workspace/model --left-dir /workspace/data/left --right-dir /workspace/data/right --output-dir /workspace/output --ckpt \"$CONTAINER_CKPT\" ${limit_arg[*]} ${mp_arg[*]} ${progress_arg[*]}"
