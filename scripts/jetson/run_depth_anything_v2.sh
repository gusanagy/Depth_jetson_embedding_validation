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
  --limit N               Copy only the first N images to a temp input dir.
  --image IMAGE           Docker image tag. Default: depth-jetson-mono:thor-jp71
EOF
}

WORKSPACE_ROOT="$HOME/Documents/depth_validation_workspace"
DATASET="all"
ENCODER="vitb"
INPUT_SIZE=518
LIMIT=0
IMAGE="depth-jetson-mono:thor-jp71"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --workspace-root) WORKSPACE_ROOT=$2; shift 2 ;;
    --dataset) DATASET=$2; shift 2 ;;
    --encoder) ENCODER=$2; shift 2 ;;
    --input-size) INPUT_SIZE=$2; shift 2 ;;
    --limit) LIMIT=$2; shift 2 ;;
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

resolve_image_dir() {
  local base=$1
  local candidate

  if find "$base" -maxdepth 1 -type f | grep -Eq '\.(png|jpe?g|bmp|tif|tiff)$'; then
    printf '%s\n' "$base"
    return 0
  fi

  for candidate in rgb images image input imgs; do
    if [[ -d "$base/$candidate" ]] && \
      find "$base/$candidate" -maxdepth 1 -type f | grep -Eq '\.(png|jpe?g|bmp|tif|tiff)$'; then
      printf '%s\n' "$base/$candidate"
      return 0
    fi
  done

  return 1
}

datasets=()
if [[ "$DATASET" == "all" ]]; then
  while IFS= read -r dir; do
    datasets+=("$(basename "$dir")")
  done < <(find "$DATASET_ROOT" -mindepth 1 -maxdepth 1 -type d | sort)
else
  datasets=("$DATASET")
fi

for ds in "${datasets[@]}"; do
  dataset_dir="$DATASET_ROOT/$ds"
  out_dir="$OUTPUT_ROOT/$ds/$ENCODER"
  temp_input_dir=""
  mount_args=(-v "$MODEL_ROOT":/workspace/model -v "$out_dir":/workspace/output)

  if [[ ! -d "$dataset_dir" ]]; then
    echo "Skipping missing dataset: $dataset_dir"
    continue
  fi

  if ! input_dir="$(resolve_image_dir "$dataset_dir")"; then
    echo "Skipping dataset without flat image dir: $dataset_dir" >&2
    continue
  fi

  container_input_dir="/workspace/model/datasets/${ds}${input_dir#"$dataset_dir"}"

  if [[ "$LIMIT" -gt 0 ]]; then
    temp_input_dir="$(mktemp -d "$WORKSPACE_ROOT/artifacts/da2_limit_${ds}_XXXXXX")"
    find "$input_dir" -maxdepth 1 -type f | sort | head -n "$LIMIT" | while IFS= read -r file; do
      cp "$file" "$temp_input_dir/"
    done
    mount_args=(-v "$MODEL_ROOT":/workspace/model -v "$out_dir":/workspace/output -v "$temp_input_dir":/workspace/temp_input:ro)
    container_input_dir="/workspace/temp_input"
  fi

  mkdir -p "$out_dir"

  echo
  echo "== DA2 dataset=$ds encoder=$ENCODER input=$(basename "$input_dir") limit=$LIMIT =="
  "${DOCKER[@]}" run --rm --runtime=nvidia \
    "${mount_args[@]}" \
    "$IMAGE" \
    bash -lc "cd /workspace/model && python3 run.py --img-path \"$container_input_dir\" --input-size \"$INPUT_SIZE\" --encoder \"$ENCODER\" --outdir /workspace/output"

  if [[ -n "$temp_input_dir" ]]; then
    rm -rf "$temp_input_dir"
  fi
done
