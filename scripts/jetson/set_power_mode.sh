#!/usr/bin/env bash

set -euo pipefail

usage() {
  cat <<'EOF'
Usage:
  set_power_mode.sh <mode-id|mode-name>
EOF
}

if [[ $# -ne 1 ]]; then
  usage
  exit 1
fi

TARGET=$1
CONF=${NVP_CONF:-/etc/nvpmodel.conf}

if [[ "$TARGET" =~ ^[0-9]+$ ]]; then
  MODE_ID=$TARGET
else
  MODE_ID=$(grep -E "< POWER_MODEL ID=[0-9]+ NAME=${TARGET}([ >]|$)" "$CONF" | \
    sed -E 's/.*ID=([0-9]+).*/\1/' | head -n 1)
fi

if [[ -z "${MODE_ID:-}" ]]; then
  echo "Power mode not found: $TARGET" >&2
  exit 1
fi

if sudo -n true >/dev/null 2>&1; then
  NVPM_CMD=(sudo -n nvpmodel)
else
  NVPM_CMD=(nvpmodel)
fi

set +e
NVPM_OUTPUT=$(printf 'no\n' | "${NVPM_CMD[@]}" -m "$MODE_ID" 2>&1)
NVPM_STATUS=$?
set -e

printf '%s\n' "$NVPM_OUTPUT"

if grep -q "Reboot required" <<<"$NVPM_OUTPUT"; then
  echo "Power mode $MODE_ID requires reboot on this Jetson." >&2
  exit 42
fi

if [[ $NVPM_STATUS -ne 0 ]]; then
  exit "$NVPM_STATUS"
fi

"${NVPM_CMD[@]}" -q
