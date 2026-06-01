#!/usr/bin/env python3

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

import torch

from depth_anything3_batch import (
    add_model_root,
    default_model_alias,
    install_evo_shim,
    install_export_shim,
    install_optional_shims,
    load_model,
)


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("--model-root", required=True)
    parser.add_argument("--input-image", required=True)
    parser.add_argument("--output-json", required=True)
    parser.add_argument("--model-name", default="da3-large")
    parser.add_argument("--model-ref", default="")
    parser.add_argument("--process-res", type=int, default=504)
    return parser.parse_args()


def profile_flops(model, image_path: str, process_res: int) -> float:
    activities = [torch.profiler.ProfilerActivity.CPU]
    if torch.cuda.is_available():
        activities.append(torch.profiler.ProfilerActivity.CUDA)

    with torch.inference_mode():
        _ = model.inference([image_path], export_dir=None, process_res=process_res, export_format="mini_npz")
        if torch.cuda.is_available():
            torch.cuda.synchronize()

    with torch.profiler.profile(activities=activities, with_flops=True) as prof:
        with torch.inference_mode():
            _ = model.inference([image_path], export_dir=None, process_res=process_res, export_format="mini_npz")
            if torch.cuda.is_available():
                torch.cuda.synchronize()

    total_flops = 0
    for event in prof.key_averages():
        if getattr(event, "flops", 0):
            total_flops += event.flops
    return float(total_flops)


def main() -> int:
    args = parse_args()
    model_root = Path(args.model_root)
    input_image = Path(args.input_image)
    output_json = Path(args.output_json)
    output_json.parent.mkdir(parents=True, exist_ok=True)

    install_optional_shims()
    install_export_shim()
    install_evo_shim()
    add_model_root(model_root)

    device = "cuda" if torch.cuda.is_available() else "cpu"
    model, resolved_model_ref = load_model(args.model_name, args.model_ref, device)
    core_model = getattr(model, "model", model)
    params = int(sum(p.numel() for p in core_model.parameters()))
    total_flops = profile_flops(model, str(input_image), args.process_res)

    payload = {
        "backend": "torch.profiler",
        "device": device,
        "flops": total_flops,
        "flops_g_per_item": total_flops / 1e9 if total_flops else None,
        "gflops": total_flops / 1e9 if total_flops else None,
        "input_image": str(input_image),
        "model_name": args.model_name,
        "model_ref": resolved_model_ref or default_model_alias(args.model_name),
        "params": params,
        "process_res": args.process_res,
    }
    output_json.write_text(json.dumps(payload, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    print(output_json)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
