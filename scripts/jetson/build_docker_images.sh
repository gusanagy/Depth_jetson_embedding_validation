#!/usr/bin/env bash

set -euo pipefail

usage() {
  cat <<'EOF'
Usage:
  build_docker_images.sh [options]

Options:
  --base-image IMAGE     Override the NVIDIA base image.
                         Default: nvcr.io/nvidia/pytorch:26.04-py3
  --only NAME            Build only one image: base, mono, stereo
  --no-cache             Disable docker build cache.
  --workspace-root PATH  Default: ~/Documents/depth_validation_workspace
  -h, --help             Show help.
EOF
}

BASE_IMAGE=${BASE_IMAGE:-nvcr.io/nvidia/pytorch:26.04-py3}
ONLY=""
NO_CACHE=0
WORKSPACE_ROOT="$HOME/Documents/depth_validation_workspace"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --base-image)
      BASE_IMAGE=$2
      shift 2
      ;;
    --only)
      ONLY=$2
      shift 2
      ;;
    --no-cache)
      NO_CACHE=1
      shift
      ;;
    --workspace-root)
      WORKSPACE_ROOT=$2
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown option: $1" >&2
      usage
      exit 1
      ;;
  esac
done

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
REPO_ROOT=$(cd "$SCRIPT_DIR/../.." && pwd)
LOG_DIR="$WORKSPACE_ROOT/docker_logs"

mkdir -p "$LOG_DIR"

if docker info >/dev/null 2>&1; then
  DOCKER_CMD=(docker)
elif sudo -n docker info >/dev/null 2>&1; then
  DOCKER_CMD=(sudo -n docker)
else
  echo "Docker is installed but not accessible for the current user." >&2
  echo "Either add the user to the docker group or allow passwordless sudo for docker." >&2
  exit 1
fi

docker_flags=()
if [[ $NO_CACHE -eq 1 ]]; then
  docker_flags+=(--no-cache)
fi

build_one() {
  local name=$1
  local file=$2
  local tag=$3
  local log_file="$LOG_DIR/build_${name}_$(date +%Y%m%d_%H%M%S).log"

  echo
  echo "== Building $name =="
  echo "Dockerfile: $file"
  echo "Tag: $tag"
  echo "Log: $log_file"

  DOCKER_BUILDKIT=1 "${DOCKER_CMD[@]}" build \
    "${docker_flags[@]}" \
    --build-arg BASE_IMAGE="$BASE_IMAGE" \
    -f "$file" \
    -t "$tag" \
    "$REPO_ROOT" | tee "$log_file"
}

case "$ONLY" in
  "")
    build_one base "$REPO_ROOT/docker/jetson/Dockerfile.base" "depth-jetson-base:thor-jp71"
    BASE_IMAGE="depth-jetson-base:thor-jp71"
    build_one mono "$REPO_ROOT/docker/jetson/Dockerfile.mono" "depth-jetson-mono:thor-jp71"
    build_one stereo "$REPO_ROOT/docker/jetson/Dockerfile.stereo" "depth-jetson-stereo:thor-jp71"
    ;;
  base)
    build_one base "$REPO_ROOT/docker/jetson/Dockerfile.base" "depth-jetson-base:thor-jp71"
    ;;
  mono)
    build_one mono "$REPO_ROOT/docker/jetson/Dockerfile.mono" "depth-jetson-mono:thor-jp71"
    ;;
  stereo)
    build_one stereo "$REPO_ROOT/docker/jetson/Dockerfile.stereo" "depth-jetson-stereo:thor-jp71"
    ;;
  *)
    echo "Invalid --only value: $ONLY" >&2
    exit 1
    ;;
esac
