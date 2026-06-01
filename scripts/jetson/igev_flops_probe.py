#!/usr/bin/env python3

from __future__ import annotations

import argparse
import json
from pathlib import Path

import torch

from igev_batch import add_model_root, list_pairs, load_image, patch_timm_for_igev


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("--model-root", required=True)
    parser.add_argument("--left-dir", required=True)
    parser.add_argument("--right-dir", required=True)
    parser.add_argument("--output-json", required=True)
    parser.add_argument("--ckpt", required=True)
    parser.add_argument("--valid-iters", type=int, default=32)
    parser.add_argument("--mixed-precision", action="store_true")
    parser.add_argument("--precision-dtype", default="float16")
    parser.add_argument("--max-disp", type=int, default=192)
    parser.add_argument("--hidden-dims", nargs="+", type=int, default=[128, 128, 128])
    parser.add_argument("--corr-levels", type=int, default=2)
    parser.add_argument("--corr-radius", type=int, default=4)
    parser.add_argument("--n-downsample", type=int, default=2)
    parser.add_argument("--n-gru-layers", type=int, default=3)
    return parser.parse_args()


def profile_flops(model, img_l: torch.Tensor, img_r: torch.Tensor, iters: int) -> float:
    activities = [torch.profiler.ProfilerActivity.CPU]
    if torch.cuda.is_available():
        activities.append(torch.profiler.ProfilerActivity.CUDA)

    with torch.inference_mode():
        _ = model(img_l, img_r, iters=iters, test_mode=True)
        if torch.cuda.is_available():
            torch.cuda.synchronize()

    with torch.profiler.profile(activities=activities, with_flops=True) as prof:
        with torch.inference_mode():
            _ = model(img_l, img_r, iters=iters, test_mode=True)
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
    patch_timm_for_igev()
    from igev_stereo import IGEVStereo
    from utils.utils import InputPadder

    device = "cuda" if torch.cuda.is_available() else "cpu"
    model = torch.nn.DataParallel(IGEVStereo(args))
    model.load_state_dict(torch.load(args.ckpt, map_location=device))
    model = model.module
    model.to(device)
    model.eval()

    pairs = list_pairs(Path(args.left_dir), Path(args.right_dir), limit=1)
    if not pairs:
        raise SystemExit("No stereo pairs found for IGEV FLOPs probe.")

    left_path, right_path = pairs[0]
    img_l = load_image(left_path, device)
    img_r = load_image(right_path, device)

    padder = InputPadder(img_l.shape, divis_by=32)
    img_l, img_r = padder.pad(img_l, img_r)

    params = int(sum(p.numel() for p in model.parameters()))
    total_flops = profile_flops(model, img_l, img_r, args.valid_iters)

    payload = {
        "backend": "torch.profiler",
        "checkpoint": args.ckpt,
        "device": device,
        "flops": total_flops,
        "flops_g_per_item": total_flops / 1e9 if total_flops else None,
        "gflops": total_flops / 1e9 if total_flops else None,
        "input_left": str(left_path),
        "input_right": str(right_path),
        "params": params,
        "valid_iters": args.valid_iters,
    }
    output_json.write_text(json.dumps(payload, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    print(output_json)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
