#!/usr/bin/env bash

set -euo pipefail

usage() {
  cat <<'EOF'
Usage:
  run_depth_anything_v2.sh [options]

Options:
  --workspace-root PATH   Default: ~/Documents/depth_validation_workspace
  --dataset NAME          Run only one dataset under datasets/. Default: all
  --encoder NAME          One of: vits, vitb, vitl. Default: vitb
  --input-size N          Default: 518
  --image IMAGE           Docker image tag. Default: depth-jetson-mono:thor-jp71
EOF
}

WORKSPACE_ROOT="$HOME/Documents/depth_validation_workspace"
DATASET="all"
ENCODER="vitb"
INPUT_SIZE=518
IMAGE="depth-jetson-mono:thor-jp71"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --workspace-root) WORKSPACE_ROOT=$2; shift 2 ;;
    --dataset) DATASET=$2; shift 2 ;;
    --encoder) ENCODER=$2; shift 2 ;;
    --input-size) INPUT_SIZE=$2; shift 2 ;;
    --image) IMAGE=$2; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) usage; exit 1 ;;
  esac
done

MODEL_ROOT="$WORKSPACE_ROOT/external_models/Depth-Anything-V2"
DATASET_ROOT="$MODEL_ROOT/datasets"
OUTPUT_ROOT="$WORKSPACE_ROOT/artifacts/da2"

if [[ ! -d "$DATASET_ROOT" ]]; then
  echo "Dataset root missing: $DATASET_ROOT" >&2
  echo "Run: bash scripts/jetson/sync_models_from_popos.sh --profile full --model da2" >&2
  exit 1
fi

if sudo -n docker info >/dev/null 2>&1; then
  DOCKER=(sudo -n docker)
else
  DOCKER=(docker)
fi

if ! "${DOCKER[@]}" image inspect "$IMAGE" >/dev/null 2>&1; then
  echo "Docker image not found: $IMAGE" >&2
  echo "Build it with: bash scripts/jetson/build_docker_images.sh --only mono" >&2
  exit 1
fi

datasets=()
if [[ "$DATASET" == "all" ]]; then
  while IFS= read -r dir; do
    datasets+=("$(basename "$dir")")
  done < <(find "$DATASET_ROOT" -mindepth 1 -maxdepth 1 -type d | sort)
else
  datasets=("$DATASET")
fi

for ds in "${datasets[@]}"; do
  input_dir="$DATASET_ROOT/$ds"
  out_dir="$OUTPUT_ROOT/$ds/$ENCODER"
  container_input_dir="/workspace/model/datasets/$ds"

  if [[ ! -d "$input_dir" ]]; then
    echo "Skipping missing dataset: $input_dir"
    continue
  fi

  mkdir -p "$out_dir"

  echo
  echo "== DA2 dataset=$ds encoder=$ENCODER =="
  "${DOCKER[@]}" run --rm --runtime=nvidia \
    -v "$MODEL_ROOT":/workspace/model \
    -v "$out_dir":/workspace/output \
    "$IMAGE" \
    bash -lc "cd /workspace/model && python3 run.py --img-path \"$container_input_dir\" --input-size \"$INPUT_SIZE\" --encoder \"$ENCODER\" --outdir /workspace/output"
done
