#!/usr/bin/env bash

set -euo pipefail

usage() {
  cat <<'EOF'
Usage:
  run_foundation_stereo.sh [options]

Options:
  --workspace-root PATH   Default: ~/Documents/depth_validation_workspace
  --dataset-root PATH     Override stereo dataset root. Default:
                          FoundationStereo/datasets/uwstereo/images/val
                          fallback: IGEV/IGEV-Stereo/uwstereo/images/val
  --ckpt PATH             Default:
                          FoundationStereo/pretrained_models/vit-large/model_large_bp2.pth
  --image IMAGE           Docker image tag. Default: depth-jetson-stereo:thor-jp71
  --limit N               Optional limit for quick tests.
  --no-progress           Disable tqdm progress bar.
EOF
}

WORKSPACE_ROOT="$HOME/Documents/depth_validation_workspace"
DATASET_ROOT=""
CKPT=""
IMAGE="depth-jetson-stereo:thor-jp71"
LIMIT=""
SHOW_PROGRESS=1

while [[ $# -gt 0 ]]; do
  case "$1" in
    --workspace-root) WORKSPACE_ROOT=$2; shift 2 ;;
    --dataset-root) DATASET_ROOT=$2; shift 2 ;;
    --ckpt) CKPT=$2; shift 2 ;;
    --image) IMAGE=$2; shift 2 ;;
    --limit) LIMIT=$2; shift 2 ;;
    --no-progress) SHOW_PROGRESS=0; shift ;;
    -h|--help) usage; exit 0 ;;
    *) usage; exit 1 ;;
  esac
done

MODEL_ROOT="$WORKSPACE_ROOT/external_models/FoundationStereo"
OUTPUT_ROOT="$WORKSPACE_ROOT/artifacts/foundation_stereo/val"
SHIM_DIR="$WORKSPACE_ROOT/artifacts/foundation_stereo_shims"
RUNNER_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
CACHE_ROOT="$WORKSPACE_ROOT/cache/foundation_stereo"

if [[ -z "$DATASET_ROOT" ]]; then
  if [[ -d "$MODEL_ROOT/datasets/uwstereo/images/val" ]]; then
    DATASET_ROOT="$MODEL_ROOT/datasets/uwstereo/images/val"
  else
    DATASET_ROOT="$WORKSPACE_ROOT/external_models/IGEV/IGEV-Stereo/uwstereo/images/val"
  fi
fi

LEFT_DIR="$DATASET_ROOT/left"
RIGHT_DIR="$DATASET_ROOT/right"
CONTAINER_DATA_ROOT="/workspace/data"

if [[ -z "$CKPT" ]]; then
  CKPT="$MODEL_ROOT/pretrained_models/vit-large/model_large_bp2.pth"
fi

if [[ ! -d "$LEFT_DIR" || ! -d "$RIGHT_DIR" ]]; then
  echo "Stereo validation directories not found under: $DATASET_ROOT" >&2
  exit 1
fi

if [[ ! -f "$CKPT" ]]; then
  echo "Checkpoint not found: $CKPT" >&2
  exit 1
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

if ! "${DOCKER[@]}" image inspect "$IMAGE" >/dev/null 2>&1; then
  echo "Docker image not found: $IMAGE" >&2
  echo "Build it with: bash scripts/jetson/build_docker_images.sh --only stereo" >&2
  exit 1
fi

mkdir -p "$OUTPUT_ROOT"
mkdir -p "$SHIM_DIR"
mkdir -p "$CACHE_ROOT/huggingface" "$CACHE_ROOT/torch"

cat > "$SHIM_DIR/open3d.py" <<'EOF'
class _UnavailableNamespace:
    def __getattr__(self, name):
        raise RuntimeError(
            "open3d shim loaded: point cloud export is unavailable in this Jetson runner"
        )


geometry = _UnavailableNamespace()
utility = _UnavailableNamespace()
io = _UnavailableNamespace()
EOF

mapfile -t left_images < <(find "$LEFT_DIR" -maxdepth 1 -type f \( -iname '*.png' -o -iname '*.jpg' -o -iname '*.jpeg' \) | sort)
total_pairs=0
for left_img in "${left_images[@]}"; do
  filename=$(basename "$left_img")
  right_img="$RIGHT_DIR/$filename"
  if [[ -f "$right_img" ]]; then
    total_pairs=$((total_pairs + 1))
  fi
done

if [[ -n "$LIMIT" && "$LIMIT" -gt 0 && "$LIMIT" -lt "$total_pairs" ]]; then
  target_pairs="$LIMIT"
else
  target_pairs="$total_pairs"
fi

echo
echo "== FoundationStereo batch =="
echo "Dataset root: $DATASET_ROOT"
echo "Pares encontrados: $total_pairs"
echo "Pares a processar: $target_pairs"

progress_args=()
if [[ $SHOW_PROGRESS -eq 1 ]]; then
  progress_args+=(--progress)
fi

limit_args=()
if [[ -n "$LIMIT" ]]; then
  limit_args+=(--limit "$LIMIT")
fi

"${DOCKER[@]}" run --rm --runtime=nvidia \
  --ipc=host \
  --ulimit memlock=-1 \
  --ulimit stack=67108864 \
  -v "$MODEL_ROOT":/workspace/model \
  -v "$DATASET_ROOT":"$CONTAINER_DATA_ROOT" \
  -v "$OUTPUT_ROOT":/workspace/output \
  -v "$SHIM_DIR":/workspace/shims:ro \
  -v "$RUNNER_ROOT":/workspace/runner:ro \
  -v "$CACHE_ROOT/huggingface":/workspace/cache/huggingface \
  -v "$CACHE_ROOT/torch":/workspace/cache/torch \
  "$IMAGE" \
  bash -lc "cd /workspace/model && export HF_HOME=/workspace/cache/huggingface TORCH_HOME=/workspace/cache/torch HF_HUB_DISABLE_PROGRESS_BARS=1 && PYTHONPATH=/workspace/shims:\$PYTHONPATH python3 /workspace/runner/scripts/jetson/foundation_stereo_batch.py --model-root /workspace/model --dataset-root \"$CONTAINER_DATA_ROOT\" --ckpt \"$CONTAINER_CKPT\" --out-dir /workspace/output ${limit_args[*]} ${progress_args[*]}"
