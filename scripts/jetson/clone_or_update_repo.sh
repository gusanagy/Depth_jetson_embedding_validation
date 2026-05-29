#!/usr/bin/env bash

set -euo pipefail

REPO_URL=${REPO_URL:-https://github.com/gusanagy/Depth_jetson_embedding_validation.git}
TARGET_DIR=${1:-"$HOME/Documents/depth_validation_workspace/depth_compare_sorriso"}
BRANCH=${BRANCH:-main}

if [[ -d "$TARGET_DIR/.git" ]]; then
  echo "Updating existing repo at $TARGET_DIR"
  git -C "$TARGET_DIR" fetch origin
  git -C "$TARGET_DIR" checkout "$BRANCH"
  git -C "$TARGET_DIR" pull --ff-only origin "$BRANCH"
else
  mkdir -p "$(dirname "$TARGET_DIR")"
  echo "Cloning $REPO_URL into $TARGET_DIR"
  git clone --branch "$BRANCH" "$REPO_URL" "$TARGET_DIR"
fi

echo "Repo ready at $TARGET_DIR"
