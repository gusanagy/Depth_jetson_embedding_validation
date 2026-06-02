#!/usr/bin/env python3

from __future__ import annotations

import argparse
import json
from pathlib import Path

import torch

from foundation_stereo_batch import add_model_root_to_path, list_pairs, load_config, patch_runtime, prepare_image


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("--model-root", required=True)
    parser.add_argument("--dataset-root", required=True)
    parser.add_argument("--ckpt", required=True)
    parser.add_argument("--output-json", required=True)
    parser.add_argument("--scale", type=float, default=1.0)
    parser.add_argument("--hiera", type=int, default=0)
    parser.add_argument("--valid-iters", type=int, default=32)
    return parser.parse_args()


def profile_flops(model, img0_tensor: torch.Tensor, img1_tensor: torch.Tensor, args) -> float:
    activities = [torch.profiler.ProfilerActivity.CPU]
    if torch.cuda.is_available():
        activities.append(torch.profiler.ProfilerActivity.CUDA)

    with torch.inference_mode(), torch.amp.autocast("cuda", enabled=torch.cuda.is_available()):
        if not args.hiera:
            _ = model.forward(img0_tensor, img1_tensor, iters=args.valid_iters, test_mode=True)
        else:
            _ = model.run_hierachical(
                img0_tensor,
                img1_tensor,
                iters=args.valid_iters,
                test_mode=True,
                small_ratio=0.5,
            )
        if torch.cuda.is_available():
            torch.cuda.synchronize()

    with torch.profiler.profile(activities=activities, with_flops=True) as prof:
        with torch.inference_mode(), torch.amp.autocast("cuda", enabled=torch.cuda.is_available()):
            if not args.hiera:
                _ = model.forward(img0_tensor, img1_tensor, iters=args.valid_iters, test_mode=True)
            else:
                _ = model.run_hierachical(
                    img0_tensor,
                    img1_tensor,
                    iters=args.valid_iters,
                    test_mode=True,
                    small_ratio=0.5,
                )
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
    dataset_root = Path(args.dataset_root)
    ckpt_path = Path(args.ckpt)
    output_json = Path(args.output_json)
    output_json.parent.mkdir(parents=True, exist_ok=True)

    patch_runtime()
    add_model_root_to_path(model_root)
    from Utils import set_logging_format, set_seed
    from core.foundation_stereo import FoundationStereo
    from core.utils.utils import InputPadder

    set_logging_format()
    set_seed(0)
    torch.autograd.set_grad_enabled(False)

    cfg = load_config(ckpt_path, args)
    device = "cuda" if torch.cuda.is_available() else "cpu"
    model = FoundationStereo(cfg)
    ckpt = torch.load(str(ckpt_path), map_location=device)
    model.load_state_dict(ckpt["model"])
    model.to(device)
    model.eval()

    pairs = list_pairs(dataset_root, 1)
    if not pairs:
        raise SystemExit("No stereo pairs found for FoundationStereo FLOPs probe.")
    left_path, right_path = pairs[0]
    img0 = prepare_image(left_path, cfg.scale)
    img1 = prepare_image(right_path, cfg.scale)
    h, w = img0.shape[:2]
    img0_tensor = torch.as_tensor(img0).float()[None].permute(0, 3, 1, 2).to(device)
    img1_tensor = torch.as_tensor(img1).float()[None].permute(0, 3, 1, 2).to(device)
    padder = InputPadder(img0_tensor.shape, divis_by=32, force_square=False)
    img0_tensor, img1_tensor = padder.pad(img0_tensor, img1_tensor)

    params = int(sum(p.numel() for p in model.parameters()))
    total_flops = profile_flops(model, img0_tensor, img1_tensor, cfg)

    payload = {
        "backend": "torch.profiler",
        "checkpoint": str(ckpt_path),
        "device": device,
        "flops": total_flops,
        "flops_g_per_item": total_flops / 1e9 if total_flops else None,
        "gflops": total_flops / 1e9 if total_flops else None,
        "height": h,
        "input_left": str(left_path),
        "input_right": str(right_path),
        "params": params,
        "scale": cfg.scale,
        "valid_iters": cfg.valid_iters,
        "width": w,
    }
    output_json.write_text(json.dumps(payload, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    print(output_json)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
