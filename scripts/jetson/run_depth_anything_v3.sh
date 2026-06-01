#!/usr/bin/env bash

set -euo pipefail

usage() {
  cat <<'EOF'
Usage:
  run_depth_anything_v3.sh [options]

Options:
  --workspace-root PATH   Default: ~/Documents/depth_validation_workspace
  --dataset NAME          Dataset name under the chosen dataset root. Default: all
  --dataset-root PATH     Override dataset root. Default: DA3 datasets fallback to DA2 datasets
  --model-name NAME       Default: da3-large
                          Alias suportado automaticamente para Hugging Face:
                          da3-small, da3-base, da3-large, da3-giant,
                          da3mono-large, da3metric-large, da3nested-giant-large
  --model-ref REF         Optional local checkpoint directory or HF repo id override
  --process-res N         Default: 504
  --limit N               Optional image limit.
  --image IMAGE           Docker image tag. Default: depth-jetson-mono:thor-jp71
  --no-progress           Disable tqdm progress bar.
EOF
}

WORKSPACE_ROOT="$HOME/Documents/depth_validation_workspace"
DATASET="all"
DATASET_ROOT=""
MODEL_NAME="da3-large"
MODEL_REF=""
PROCESS_RES=504
LIMIT=0
IMAGE="depth-jetson-mono:thor-jp71"
SHOW_PROGRESS=1

while [[ $# -gt 0 ]]; do
  case "$1" in
    --workspace-root) WORKSPACE_ROOT=$2; shift 2 ;;
    --dataset) DATASET=$2; shift 2 ;;
    --dataset-root) DATASET_ROOT=$2; shift 2 ;;
    --model-name) MODEL_NAME=$2; shift 2 ;;
    --model-ref) MODEL_REF=$2; shift 2 ;;
    --process-res) PROCESS_RES=$2; shift 2 ;;
    --limit) LIMIT=$2; shift 2 ;;
    --image) IMAGE=$2; shift 2 ;;
    --no-progress) SHOW_PROGRESS=0; shift ;;
    -h|--help) usage; exit 0 ;;
    *) usage; exit 1 ;;
  esac
done

MODEL_ROOT="$WORKSPACE_ROOT/external_models/depth-anything-3"
OUTPUT_ROOT="$WORKSPACE_ROOT/artifacts/da3"
CACHE_ROOT="$WORKSPACE_ROOT/cache/depth_anything_v3"

if [[ -z "$DATASET_ROOT" ]]; then
  if [[ -d "$MODEL_ROOT/datasets" ]]; then
    DATASET_ROOT="$MODEL_ROOT/datasets"
  else
    DATASET_ROOT="$WORKSPACE_ROOT/external_models/Depth-Anything-V2/datasets"
  fi
fi

if [[ ! -d "$DATASET_ROOT" ]]; then
  echo "Dataset root missing: $DATASET_ROOT" >&2
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

to_container_model_ref() {
  local ref=$1
  if [[ -z "$ref" ]]; then
    return 1
  fi
  if [[ "$ref" == "$MODEL_ROOT"* ]]; then
    printf '/workspace/model/%s\n' "${ref#$MODEL_ROOT/}"
    return 0
  fi
  if [[ "$ref" == /* ]]; then
    echo "Model ref must be inside $MODEL_ROOT or be a Hugging Face repo id: $ref" >&2
    exit 1
  fi
  printf '%s\n' "$ref"
}

resolve_local_model_ref() {
  local normalized_name=${MODEL_NAME//-/_}
  local candidate
  local patterns=(
    "$MODEL_ROOT/checkpoints/$MODEL_NAME"
    "$MODEL_ROOT/checkpoints/$normalized_name"
    "$MODEL_ROOT/pretrained_models/$MODEL_NAME"
    "$MODEL_ROOT/pretrained_models/$normalized_name"
    "$MODEL_ROOT/pretrained/$MODEL_NAME"
    "$MODEL_ROOT/pretrained/$normalized_name"
    "$MODEL_ROOT/models/$MODEL_NAME"
    "$MODEL_ROOT/models/$normalized_name"
    "$MODEL_ROOT/weights/$MODEL_NAME"
    "$MODEL_ROOT/weights/$normalized_name"
    "$MODEL_ROOT/$MODEL_NAME"
    "$MODEL_ROOT/$normalized_name"
  )

  for candidate in "${patterns[@]}"; do
    if [[ -d "$candidate" ]]; then
      printf '%s\n' "$candidate"
      return 0
    fi
  done

  while IFS= read -r candidate; do
    if [[ -n "$candidate" ]]; then
      printf '%s\n' "$candidate"
      return 0
    fi
  done < <(find "$MODEL_ROOT" -maxdepth 4 -type d \
    \( -iname "*$MODEL_NAME*" -o -iname "*$normalized_name*" \) | sort)

  return 1
}

resolve_image_dir() {
  local base=$1
  local candidate
  local first_image=""

  first_image=$(find "$base" -maxdepth 1 -type f \
    \( -iname '*.png' -o -iname '*.jpg' -o -iname '*.jpeg' -o -iname '*.bmp' -o -iname '*.tif' -o -iname '*.tiff' \) \
    -print -quit 2>/dev/null || true)
  if [[ -n "$first_image" ]]; then
    printf '%s\n' "$base"
    return 0
  fi

  for candidate in rgb images image input imgs; do
    first_image=$(find "$base/$candidate" -maxdepth 1 -type f \
      \( -iname '*.png' -o -iname '*.jpg' -o -iname '*.jpeg' -o -iname '*.bmp' -o -iname '*.tif' -o -iname '*.tiff' \) \
      -print -quit 2>/dev/null || true)
    if [[ -d "$base/$candidate" && -n "$first_image" ]]; then
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

mkdir -p "$OUTPUT_ROOT" "$CACHE_ROOT/huggingface" "$CACHE_ROOT/torch"

resolved_model_ref=""
if [[ -n "$MODEL_REF" ]]; then
  resolved_model_ref=$(to_container_model_ref "$MODEL_REF")
elif local_ref="$(resolve_local_model_ref)"; then
  resolved_model_ref=$(to_container_model_ref "$local_ref")
fi

for ds in "${datasets[@]}"; do
  dataset_dir="$DATASET_ROOT/$ds"
  if [[ ! -d "$dataset_dir" ]]; then
    echo "Skipping missing dataset: $dataset_dir"
    continue
  fi

  if ! input_dir="$(resolve_image_dir "$dataset_dir")"; then
    echo "Skipping dataset without flat image dir: $dataset_dir" >&2
    continue
  fi

  out_dir="$OUTPUT_ROOT/$ds/$MODEL_NAME"
  mkdir -p "$out_dir"

  progress_arg=()
  if [[ $SHOW_PROGRESS -eq 0 ]]; then
    progress_arg+=(--no-progress)
  fi

  limit_arg=()
  if [[ "$LIMIT" -gt 0 ]]; then
    limit_arg+=(--limit "$LIMIT")
  fi

  echo
  if [[ -n "$resolved_model_ref" ]]; then
    echo "== DA3 dataset=$ds model=$MODEL_NAME ref=$resolved_model_ref input=$(basename "$input_dir") limit=$LIMIT =="
  else
    echo "== DA3 dataset=$ds model=$MODEL_NAME input=$(basename "$input_dir") limit=$LIMIT =="
  fi
  "${DOCKER[@]}" run --rm --runtime=nvidia \
    --ipc=host \
    --ulimit memlock=-1 \
    --ulimit stack=67108864 \
    -v "$MODEL_ROOT":/workspace/model \
    -v "$input_dir":/workspace/input:ro \
    -v "$out_dir":/workspace/output \
    -v "$WORKSPACE_ROOT/depth_compare_sorriso":/workspace/runner:ro \
    -v "$CACHE_ROOT/huggingface":/workspace/cache/huggingface \
    -v "$CACHE_ROOT/torch":/workspace/cache/torch \
    "$IMAGE" \
    bash -lc "export HF_HOME=/workspace/cache/huggingface TORCH_HOME=/workspace/cache/torch PYTHONPATH=/workspace/model/src:\$PYTHONPATH && python3 /workspace/runner/scripts/jetson/depth_anything3_batch.py --model-root /workspace/model --input-dir /workspace/input --output-dir /workspace/output --model-name \"$MODEL_NAME\" ${resolved_model_ref:+--model-ref \"$resolved_model_ref\"} --process-res \"$PROCESS_RES\" ${limit_arg[*]} ${progress_arg[*]}"
done
