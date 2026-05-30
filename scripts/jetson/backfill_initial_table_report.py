#!/usr/bin/env python3

from __future__ import annotations

import argparse
import csv
import json
from pathlib import Path
from typing import Any


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Backfill processed item counts and derived metrics for an initial table report.")
    parser.add_argument("--report-root", required=True, help="Path to reports/initial_table/<label>")
    parser.add_argument("--write-enriched-summary", action="store_true", help="Write summary_enriched.json/csv/jsonl")
    return parser.parse_args()


def load_json(path: Path) -> Any:
    return json.loads(path.read_text(encoding="utf-8"))


def count_da2_items(artifacts_dir: Path) -> int:
    return sum(1 for _ in artifacts_dir.glob("*/*/grayscale/*.png"))


def count_foundation_items(artifacts_dir: Path) -> int | None:
    info_path = artifacts_dir / "val" / "batch_run_info.json"
    if not info_path.exists():
        return None
    return load_json(info_path).get("processed_pairs")


def guess_flops_g_per_item(row: dict[str, Any]) -> float | None:
    report_dir = row.get("report_dir")
    if not report_dir:
        return None

    candidates = [
        Path(report_dir) / "flops.json",
        Path(report_dir) / "report_flops.json",
    ]
    for candidate in candidates:
        if not candidate.exists():
            continue
        data = load_json(candidate)
        if data.get("flops_g_per_item") is not None:
            return float(data["flops_g_per_item"])
        if data.get("flops_per_item") is not None:
            return float(data["flops_per_item"]) / 1e9
        if data.get("flops") is not None:
            return float(data["flops"]) / 1e9
    return None


def enrich_row(row: dict[str, Any]) -> dict[str, Any]:
    enriched = dict(row)
    model_key = row.get("model_key")
    artifacts_dir_raw = row.get("artifacts_dir")
    processed_items = row.get("processed_items")
    processed_unit = row.get("processed_unit")

    if row.get("status") == "completed" and artifacts_dir_raw:
        artifacts_dir = Path(artifacts_dir_raw)
        if artifacts_dir.exists():
            if model_key == "depth_anything_v2":
                counted = count_da2_items(artifacts_dir)
                if counted > 0:
                    processed_items = counted
                    processed_unit = "images"
            elif model_key == "foundation_stereo":
                counted = count_foundation_items(artifacts_dir)
                if counted is not None and counted > 0:
                    processed_items = counted
                    processed_unit = "stereo_pairs"

    duration_s = row.get("duration_s")
    energy_joules = row.get("energy_joules")
    telemetry_samples = row.get("samples")
    throughput_items_s = None
    joules_per_item = None

    if processed_items and duration_s:
        throughput_items_s = processed_items / duration_s
    if processed_items and energy_joules:
        joules_per_item = energy_joules / processed_items

    flops_g_per_item = guess_flops_g_per_item(row)
    jgflops = None
    if flops_g_per_item and joules_per_item:
        jgflops = joules_per_item / flops_g_per_item

    enriched["telemetry_samples"] = telemetry_samples
    enriched["processed_items"] = processed_items
    enriched["processed_unit"] = processed_unit
    enriched["throughput_items_s"] = throughput_items_s
    enriched["joules_per_item"] = joules_per_item
    enriched["flops_g_per_item"] = flops_g_per_item
    enriched["jgflops"] = jgflops
    return enriched


def write_csv(path: Path, rows: list[dict[str, Any]]) -> None:
    fieldnames = [
        "model_key",
        "model_name",
        "status",
        "power_mode_id",
        "power_mode_name",
        "profile",
        "dataset_scope",
        "duration_s",
        "energy_joules",
        "avg_power_w",
        "peak_power_w",
        "primary_power_rail",
        "telemetry_samples",
        "processed_items",
        "processed_unit",
        "throughput_items_s",
        "joules_per_item",
        "flops_g_per_item",
        "jgflops",
        "artifacts_dir",
        "report_dir",
        "notes",
    ]
    with path.open("w", encoding="utf-8", newline="") as handle:
        writer = csv.DictWriter(handle, fieldnames=fieldnames)
        writer.writeheader()
        for row in rows:
            writer.writerow({key: row.get(key) for key in fieldnames})


def write_jsonl(path: Path, rows: list[dict[str, Any]]) -> None:
    with path.open("w", encoding="utf-8") as handle:
        for row in rows:
            handle.write(json.dumps(row, sort_keys=True) + "\n")


def main() -> int:
    args = parse_args()
    report_root = Path(args.report_root)
    summary_json = report_root / "summary.json"
    rows = load_json(summary_json)
    enriched_rows = [enrich_row(row) for row in rows]

    if args.write_enriched_summary:
        (report_root / "summary_enriched.json").write_text(
            json.dumps(enriched_rows, indent=2, sort_keys=True) + "\n",
            encoding="utf-8",
        )
        write_csv(report_root / "summary_enriched.csv", enriched_rows)
        write_jsonl(report_root / "summary_enriched.jsonl", enriched_rows)
        print(report_root / "summary_enriched.json")
    else:
        print(json.dumps(enriched_rows, indent=2, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
