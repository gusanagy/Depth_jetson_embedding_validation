#!/usr/bin/env python3

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

import torch
from PIL import Image


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("--model-root", required=True)
    parser.add_argument("--input-image", required=True)
    parser.add_argument("--output-json", required=True)
    parser.add_argument("--checkpoint", default="prs-eth/marigold-depth-v1-1")
    parser.add_argument("--denoise-steps", type=int, default=4)
    parser.add_argument("--ensemble-size", type=int, default=1)
    parser.add_argument("--processing-res", type=int, default=384)
    parser.add_argument("--fp16", action="store_true")
    return parser.parse_args()


def add_model_root(model_root: Path) -> None:
    sys.path.insert(0, str(model_root))


def profile_flops(pipe, image, args) -> float:
    activities = [torch.profiler.ProfilerActivity.CPU]
    if torch.cuda.is_available():
        activities.append(torch.profiler.ProfilerActivity.CUDA)

    with torch.inference_mode():
        _ = pipe(
            image,
            denoising_steps=args.denoise_steps,
            ensemble_size=args.ensemble_size,
            processing_res=args.processing_res,
            show_progress_bar=False,
        )
        if torch.cuda.is_available():
            torch.cuda.synchronize()

    with torch.profiler.profile(activities=activities, with_flops=True) as prof:
        with torch.inference_mode():
            _ = pipe(
                image,
                denoising_steps=args.denoise_steps,
                ensemble_size=args.ensemble_size,
                processing_res=args.processing_res,
                show_progress_bar=False,
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
    output_json = Path(args.output_json)
    output_json.parent.mkdir(parents=True, exist_ok=True)

    add_model_root(model_root)
    from marigold import MarigoldDepthPipeline

    device = torch.device("cuda" if torch.cuda.is_available() else "cpu")
    dtype = torch.float16 if args.fp16 and device.type == "cuda" else torch.float32
    variant = "fp16" if dtype == torch.float16 else None
    pipe = MarigoldDepthPipeline.from_pretrained(args.checkpoint, variant=variant, torch_dtype=dtype)
    try:
        pipe.enable_xformers_memory_efficient_attention()
    except Exception:
        pass
    pipe = pipe.to(device)

    image = Image.open(args.input_image).convert("RGB")
    params = int(sum(p.numel() for p in pipe.unet.parameters()))
    total_flops = profile_flops(pipe, image, args)

    payload = {
        "backend": "torch.profiler",
        "checkpoint": args.checkpoint,
        "denoise_steps": args.denoise_steps,
        "device": str(device),
        "ensemble_size": args.ensemble_size,
        "flops": total_flops,
        "flops_g_per_item": total_flops / 1e9 if total_flops else None,
        "gflops": total_flops / 1e9 if total_flops else None,
        "input_image": str(args.input_image),
        "params": params,
        "processing_res": args.processing_res,
    }
    output_json.write_text(json.dumps(payload, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    print(output_json)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
