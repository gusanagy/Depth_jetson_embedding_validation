#!/usr/bin/env bash

set -euo pipefail

usage() {
  cat <<'EOF'
Usage:
  run_with_tegrastats.sh <log_dir> -- <command> [args...]

Environment variables:
  TEGRA_INTERVAL_MS   Sampling interval in milliseconds. Default: 200
  TEGRA_BIN           tegrastats binary path. Default: tegrastats
  THERMAL_MAX_TEMP_C  If > 0, aborts the command when any tegrastats sensor
                      reaches this temperature in Celsius. Default: 0 (disabled)

Example:
  ./scripts/benchmark/run_with_tegrastats.sh \
    benchmarks/logs/da2_suim -- \
    docker run --rm depth-jetson-mono python run_da2.py --input /data/suim
EOF
}

if [[ $# -lt 3 ]]; then
  usage
  exit 1
fi

LOG_DIR=$1
shift

if [[ ${1:-} != "--" ]]; then
  usage
  exit 1
fi
shift

if [[ $# -eq 0 ]]; then
  usage
  exit 1
fi

COMMAND=("$@")

TEGRA_INTERVAL_MS=${TEGRA_INTERVAL_MS:-200}
TEGRA_BIN=${TEGRA_BIN:-tegrastats}
THERMAL_MAX_TEMP_C=${THERMAL_MAX_TEMP_C:-0}

mkdir -p "$LOG_DIR"

TEGRALOG="$LOG_DIR/tegrastats.log"
CMD_STDOUT="$LOG_DIR/command.stdout.log"
CMD_STDERR="$LOG_DIR/command.stderr.log"
META_JSON="$LOG_DIR/run_meta.json"
THERMAL_EVENT_JSON="$LOG_DIR/thermal_event.json"

if ! command -v "$TEGRA_BIN" >/dev/null 2>&1; then
  echo "Erro: '$TEGRA_BIN' nao encontrado. Rode este wrapper no host Jetson." >&2
  exit 2
fi

cleanup() {
  set +e
  if [[ -n "${CMD_PID:-}" ]]; then
    kill "$CMD_PID" >/dev/null 2>&1 || true
    pkill -TERM -P "$CMD_PID" >/dev/null 2>&1 || true
  fi
  if [[ -n "${TEGRA_PID:-}" ]]; then
    kill "$TEGRA_PID" >/dev/null 2>&1 || true
  fi
  "$TEGRA_BIN" --stop >/dev/null 2>&1 || true
}

trap cleanup EXIT INT TERM

START_TS=$(date +%s.%N)
START_ISO=$(date --iso-8601=seconds)

echo "Executando comando: ${COMMAND[*]}"
set +e
"${COMMAND[@]}" > >(tee "$CMD_STDOUT") 2> >(tee "$CMD_STDERR" >&2) &
CMD_PID=$!
set -e

echo "Iniciando tegrastats em $TEGRALOG"
(
  set +e
  stdbuf -oL "$TEGRA_BIN" --interval "$TEGRA_INTERVAL_MS" 2>/dev/null | \
    while IFS= read -r line; do
      timestamp=$(date +%s.%N)
      printf '%s %s\n' "$timestamp" "$line"

      if [[ "$THERMAL_MAX_TEMP_C" =~ ^[0-9]+$ ]] && (( THERMAL_MAX_TEMP_C > 0 )); then
        max_temp=-1
        max_sensor=""
        for token in $line; do
          if [[ "$token" =~ ^([A-Za-z0-9_]+)@([0-9]+)(\.[0-9]+)?C$ ]]; then
            sensor=${BASH_REMATCH[1]}
            temp_c=${BASH_REMATCH[2]}
            if (( temp_c > max_temp )); then
              max_temp=$temp_c
              max_sensor=$sensor
            fi
          fi
        done

        if (( max_temp >= THERMAL_MAX_TEMP_C )); then
          cat >"$THERMAL_EVENT_JSON" <<EOF
{
  "event": "thermal_cutoff",
  "threshold_c": $THERMAL_MAX_TEMP_C,
  "sensor": "$max_sensor",
  "observed_temp_c": $max_temp,
  "timestamp": "$timestamp"
}
EOF
          echo "Thermal cutoff triggered at ${max_sensor}@${max_temp}C (threshold ${THERMAL_MAX_TEMP_C}C)" >&2
          kill "$CMD_PID" >/dev/null 2>&1 || true
          pkill -TERM -P "$CMD_PID" >/dev/null 2>&1 || true
          break
        fi
      fi
    done
) >"$TEGRALOG" &
TEGRA_PID=$!

set +e
wait "$CMD_PID"
CMD_STATUS=$?
set -e

END_TS=$(date +%s.%N)
END_ISO=$(date --iso-8601=seconds)

cleanup
trap - EXIT INT TERM

DURATION_S=$(python3 - <<PY
start = float("$START_TS")
end = float("$END_TS")
print(f"{end - start:.6f}")
PY
)

COMMAND_JSON=$(python3 -c 'import json, sys; print(json.dumps(sys.argv[1:]))' "${COMMAND[@]}")

cat >"$META_JSON" <<EOF
{
  "command": $COMMAND_JSON,
  "start_iso": "$START_ISO",
  "end_iso": "$END_ISO",
  "duration_s": $DURATION_S,
  "exit_code": $CMD_STATUS,
  "thermal_event_json": "$THERMAL_EVENT_JSON",
  "thermal_protection_enabled": $( [[ "$THERMAL_MAX_TEMP_C" =~ ^[0-9]+$ ]] && (( THERMAL_MAX_TEMP_C > 0 )) && echo true || echo false ),
  "thermal_max_temp_c": $THERMAL_MAX_TEMP_C,
  "tegrastats_interval_ms": $TEGRA_INTERVAL_MS,
  "tegrastats_log": "$TEGRALOG",
  "stdout_log": "$CMD_STDOUT",
  "stderr_log": "$CMD_STDERR"
}
EOF

echo "Execucao finalizada com codigo $CMD_STATUS"
echo "Metadados: $META_JSON"

exit "$CMD_STATUS"
