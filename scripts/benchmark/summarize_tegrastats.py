#!/usr/bin/env python3

from __future__ import annotations

import argparse
import json
import math
import re
from pathlib import Path
from statistics import mean


TS_RE = re.compile(r"^(?P<ts>\d+\.\d+)\s+(?P<body>.*)$")
RAM_RE = re.compile(r"RAM\s+(?P<used>\d+)/(?P<total>\d+)MB")
GR3D_RE = re.compile(r"GR3D_FREQ\s+(?P<util>\d+)%@?(?P<freq>\d+)?")
EMC_RE = re.compile(r"EMC_FREQ\s+(?P<util>\d+)%@?(?P<freq>\d+)?")
CPU_RE = re.compile(r"CPU\s+\[(?P<body>[^\]]+)\]")
TEMP_RE = re.compile(r"(?P<name>[A-Za-z0-9_]+)@(?P<temp>\d+(?:\.\d+)?)C")
RAIL_RE = re.compile(r"(?P<rail>[A-Z0-9_]+)\s+(?P<inst>\d+)mW/(?P<avg>\d+)mW")

PRIMARY_POWER_RAILS = (
    "VDD_IN",
    "POM_5V_IN",
    "VIN_SYS_5V0",
    "VDD_CPU_GPU_CV",
)


def parse_cpu_util(body: str) -> float | None:
    values: list[float] = []
    for item in body.split(","):
        item = item.strip()
        if item == "off":
            continue
        if "%" not in item:
            continue
        try:
            values.append(float(item.split("%", 1)[0]))
        except ValueError:
            continue
    if not values:
        return None
    return mean(values)


def pick_power_rail(rails_seen: set[str]) -> str | None:
    for rail in PRIMARY_POWER_RAILS:
        if rail in rails_seen:
            return rail
    return next(iter(sorted(rails_seen)), None)


def main() -> int:
    parser = argparse.ArgumentParser(description="Summarize a tegrastats log into JSON.")
    parser.add_argument("log_path", type=Path)
    parser.add_argument("--default-interval-ms", type=float, default=200.0)
    parser.add_argument("--output", type=Path)
    args = parser.parse_args()

    samples = 0
    ram_used: list[float] = []
    ram_total: list[float] = []
    gr3d_util: list[float] = []
    gr3d_freq: list[float] = []
    emc_util: list[float] = []
    cpu_util: list[float] = []
    temps: dict[str, list[float]] = {}
    rails: dict[str, list[float]] = {}
    timestamps: list[float] = []

    with args.log_path.open("r", encoding="utf-8", errors="replace") as fh:
        for raw_line in fh:
            line = raw_line.strip()
            if not line:
                continue

            body = line
            ts_match = TS_RE.match(line)
            if ts_match:
                timestamps.append(float(ts_match.group("ts")))
                body = ts_match.group("body")

            ram_match = RAM_RE.search(body)
            if ram_match:
                ram_used.append(float(ram_match.group("used")))
                ram_total.append(float(ram_match.group("total")))

            gr3d_match = GR3D_RE.search(body)
            if gr3d_match:
                gr3d_util.append(float(gr3d_match.group("util")))
                if gr3d_match.group("freq"):
                    gr3d_freq.append(float(gr3d_match.group("freq")))

            emc_match = EMC_RE.search(body)
            if emc_match:
                emc_util.append(float(emc_match.group("util")))

            cpu_match = CPU_RE.search(body)
            if cpu_match:
                cpu_value = parse_cpu_util(cpu_match.group("body"))
                if cpu_value is not None:
                    cpu_util.append(cpu_value)

            for temp_match in TEMP_RE.finditer(body):
                temps.setdefault(temp_match.group("name"), []).append(float(temp_match.group("temp")))

            for rail_match in RAIL_RE.finditer(body):
                rails.setdefault(rail_match.group("rail"), []).append(float(rail_match.group("inst")))

            samples += 1

    if samples == 0:
        raise SystemExit(f"Nenhuma amostra encontrada em {args.log_path}")

    rail_name = pick_power_rail(set(rails))
    primary_power = rails.get(rail_name, [])

    if len(timestamps) >= 2:
        deltas = [max(0.0, b - a) for a, b in zip(timestamps, timestamps[1:])]
        avg_delta = mean(deltas) if deltas else args.default_interval_ms / 1000.0
    else:
        avg_delta = args.default_interval_ms / 1000.0

    energy_j = 0.0
    if primary_power:
        if len(timestamps) == len(primary_power) and len(primary_power) >= 2:
            for idx in range(1, len(primary_power)):
                dt = max(0.0, timestamps[idx] - timestamps[idx - 1])
                energy_j += (primary_power[idx - 1] / 1000.0) * dt
        else:
            energy_j = sum((value / 1000.0) * avg_delta for value in primary_power)

    summary = {
        "samples": samples,
        "sample_interval_s_estimate": round(avg_delta, 6),
        "ram_used_mb_avg": round(mean(ram_used), 3) if ram_used else None,
        "ram_used_mb_max": round(max(ram_used), 3) if ram_used else None,
        "ram_total_mb": round(mean(ram_total), 3) if ram_total else None,
        "cpu_util_avg_pct": round(mean(cpu_util), 3) if cpu_util else None,
        "gr3d_util_avg_pct": round(mean(gr3d_util), 3) if gr3d_util else None,
        "gr3d_util_max_pct": round(max(gr3d_util), 3) if gr3d_util else None,
        "gr3d_freq_avg_mhz": round(mean(gr3d_freq), 3) if gr3d_freq else None,
        "emc_util_avg_pct": round(mean(emc_util), 3) if emc_util else None,
        "primary_power_rail": rail_name,
        "primary_power_avg_mw": round(mean(primary_power), 3) if primary_power else None,
        "primary_power_max_mw": round(max(primary_power), 3) if primary_power else None,
        "energy_j": round(energy_j, 6) if primary_power else None,
        "temperatures_c_avg": {
            key: round(mean(values), 3) for key, values in sorted(temps.items())
        },
        "power_rails_avg_mw": {
            key: round(mean(values), 3) for key, values in sorted(rails.items())
        },
    }

    encoded = json.dumps(summary, indent=2, sort_keys=True)

    if args.output:
        args.output.parent.mkdir(parents=True, exist_ok=True)
        args.output.write_text(encoded + "\n", encoding="utf-8")
    else:
        print(encoded)

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
