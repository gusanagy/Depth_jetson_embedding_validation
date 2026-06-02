#!/usr/bin/env python3

from __future__ import annotations

import argparse
import json
import os
import sys
from pathlib import Path

import torch


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("--model-root", required=True)
    parser.add_argument("--input-image", required=True)
    parser.add_argument("--output-json", required=True)
    return parser.parse_args()


def add_model_root(model_root: Path) -> None:
    sys.path.insert(0, str(model_root / "src"))


def profile_flops(model, image, f_px: float) -> float:
    activities = [torch.profiler.ProfilerActivity.CPU]
    if torch.cuda.is_available():
        activities.append(torch.profiler.ProfilerActivity.CUDA)

    with torch.inference_mode():
        _ = model.infer(image, f_px=f_px)
        if torch.cuda.is_available():
            torch.cuda.synchronize()

    with torch.profiler.profile(activities=activities, with_flops=True) as prof:
        with torch.inference_mode():
            _ = model.infer(image, f_px=f_px)
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
    output_json = Path(args.output_json)
    output_json.parent.mkdir(parents=True, exist_ok=True)

    add_model_root(model_root)
    from depth_pro import create_model_and_transforms, load_rgb

    os.chdir(model_root)
    device = torch.device("cuda:0" if torch.cuda.is_available() else "cpu")
    model, transform = create_model_and_transforms(
        device=device,
        precision=torch.half if device.type == "cuda" else torch.float32,
    )
    model.eval()

    image, _, f_px = load_rgb(Path(args.input_image))
    image = transform(image)
    params = int(sum(p.numel() for p in model.parameters()))
    total_flops = profile_flops(model, image, f_px)

    payload = {
        "backend": "torch.profiler",
        "device": str(device),
        "flops": total_flops,
        "flops_g_per_item": total_flops / 1e9 if total_flops else None,
        "gflops": total_flops / 1e9 if total_flops else None,
        "input_image": str(args.input_image),
        "params": params,
    }
    output_json.write_text(json.dumps(payload, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    print(output_json)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
