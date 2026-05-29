#!/usr/bin/env bash

set -euo pipefail

if sudo -n true >/dev/null 2>&1; then
  NVPM_CMD=(sudo -n nvpmodel)
else
  NVPM_CMD=(nvpmodel)
fi

OUTPUT=$("${NVPM_CMD[@]}" -q 2>/dev/null)
MODE_NAME=$(awk -F': ' '/NV Power Mode:/{print $2; exit}' <<<"$OUTPUT")
MODE_ID=$(awk '/^[0-9]+$/{print $1; exit}' <<<"$OUTPUT")

if [[ -z "${MODE_ID:-}" || -z "${MODE_NAME:-}" ]]; then
  echo "Unable to determine current power mode from nvpmodel -q output." >&2
  echo "$OUTPUT" >&2
  exit 1
fi

printf '%s\t%s\n' "$MODE_ID" "$MODE_NAME"
