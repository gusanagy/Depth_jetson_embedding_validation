#!/usr/bin/env python3

from __future__ import annotations

import argparse
import csv
import json
from pathlib import Path


def load_json(path: Path) -> dict:
    return json.loads(path.read_text(encoding="utf-8"))


def resolve_mode_dir(report_root: Path, mode: dict) -> Path:
    if mode.get("result_dir"):
        return Path(mode["result_dir"])

    prefix = f"{mode['id']}_{mode['name']}"
    candidates = sorted(report_root.glob(f"{prefix}*"))
    if candidates:
        return candidates[0]

    return report_root / prefix


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--workspace-root", default="~/Documents/depth_validation_workspace")
    parser.add_argument("--label", required=True)
    args = parser.parse_args()

    workspace_root = Path(args.workspace_root).expanduser()
    report_root = workspace_root / "reports" / "tegrastats" / args.label
    plan_path = report_root / "plan.json"

    if not plan_path.exists():
        raise SystemExit(f"Plan not found: {plan_path}")

    plan = load_json(plan_path)
    rows: list[dict[str, object]] = []
    for mode in plan.get("modes", []):
        mode_dir = resolve_mode_dir(report_root, mode)
        row = {
            "power_mode_id": mode["id"],
            "power_mode_name": mode["name"],
            "status": mode.get("status"),
            "result_dir": str(mode_dir),
            "duration_s": None,
            "energy_joules": None,
            "avg_power_w": None,
            "peak_power_w": None,
            "primary_power_rail": None,
            "samples": None,
            "gflops": None,
            "jgflops": None,
        }

        summary_path = mode_dir / "tegrastats_summary.json"
        skipped_path = mode_dir / "skipped.json"
        if summary_path.exists():
            summary = load_json(summary_path)
            for key in (
                "duration_s",
                "energy_joules",
                "avg_power_w",
                "peak_power_w",
                "primary_power_rail",
                "samples",
                "gflops",
                "jgflops",
            ):
                row[key] = summary.get(key)
        elif skipped_path.exists():
            skipped = load_json(skipped_path)
            row["status"] = skipped.get("status", row["status"])

        rows.append(row)

    json_path = report_root / "summary.json"
    csv_path = report_root / "summary.csv"
    json_path.write_text(json.dumps(rows, indent=2, sort_keys=True) + "\n", encoding="utf-8")

    fieldnames = [
        "power_mode_id",
        "power_mode_name",
        "status",
        "duration_s",
        "energy_joules",
        "avg_power_w",
        "peak_power_w",
        "primary_power_rail",
        "samples",
        "gflops",
        "jgflops",
        "result_dir",
    ]
    with csv_path.open("w", encoding="utf-8", newline="") as fh:
        writer = csv.DictWriter(fh, fieldnames=fieldnames)
        writer.writeheader()
        writer.writerows(rows)

    print(f"Summary JSON: {json_path}")
    print(f"Summary CSV: {csv_path}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
