#!/usr/bin/env python3

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

import cv2
import torch


MODEL_CONFIGS = {
    "vits": {"encoder": "vits", "features": 64, "out_channels": [48, 96, 192, 384]},
    "vitb": {"encoder": "vitb", "features": 128, "out_channels": [96, 192, 384, 768]},
    "vitl": {"encoder": "vitl", "features": 256, "out_channels": [256, 512, 1024, 1024]},
}


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("--model-root", required=True)
    parser.add_argument("--input-image", required=True)
    parser.add_argument("--output-json", required=True)
    parser.add_argument("--encoder", default="vitb", choices=sorted(MODEL_CONFIGS))
    parser.add_argument("--input-size", type=int, default=518)
    return parser.parse_args()


def add_model_root(model_root: Path) -> None:
    sys.path.insert(0, str(model_root))


def profile_flops(model, raw_image, input_size: int) -> float:
    activities = [torch.profiler.ProfilerActivity.CPU]
    if torch.cuda.is_available():
        activities.append(torch.profiler.ProfilerActivity.CUDA)

    with torch.inference_mode():
        _ = model.infer_image(raw_image, input_size)
        if torch.cuda.is_available():
            torch.cuda.synchronize()

    with torch.profiler.profile(activities=activities, with_flops=True) as prof:
        with torch.inference_mode():
            _ = model.infer_image(raw_image, input_size)
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
    from depth_anything_v2.dpt import DepthAnythingV2

    checkpoint = model_root / "checkpoints" / f"depth_anything_v2_{args.encoder}.pth"
    if not checkpoint.exists():
        raise SystemExit(f"Checkpoint not found: {checkpoint}")

    device = "cuda" if torch.cuda.is_available() else "cpu"
    model = DepthAnythingV2(**MODEL_CONFIGS[args.encoder])
    state_dict = torch.load(checkpoint, map_location="cpu")
    model.load_state_dict(state_dict)
    model.to(device).eval()

    raw_image = cv2.imread(str(args.input_image))
    if raw_image is None:
        raise SystemExit(f"Could not read image: {args.input_image}")

    params = int(sum(p.numel() for p in model.parameters()))
    total_flops = profile_flops(model, raw_image, args.input_size)

    payload = {
        "backend": "torch.profiler",
        "checkpoint": str(checkpoint),
        "device": device,
        "encoder": args.encoder,
        "flops": total_flops,
        "flops_g_per_item": total_flops / 1e9 if total_flops else None,
        "gflops": total_flops / 1e9 if total_flops else None,
        "input_image": str(args.input_image),
        "input_size": args.input_size,
        "params": params,
    }
    output_json.write_text(json.dumps(payload, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    print(output_json)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
