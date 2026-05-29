#!/usr/bin/env python3

import argparse
import runpy
import sys

import torch


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--script", required=True)
    parser.add_argument("script_args", nargs=argparse.REMAINDER)
    args = parser.parse_args()

    original_torch_load = torch.load

    def patched_torch_load(*load_args, **load_kwargs):
        load_kwargs.setdefault("weights_only", False)
        return original_torch_load(*load_args, **load_kwargs)

    torch.load = patched_torch_load

    forwarded_args = args.script_args
    if forwarded_args and forwarded_args[0] == "--":
        forwarded_args = forwarded_args[1:]

    sys.argv = [args.script, *forwarded_args]
    runpy.run_path(args.script, run_name="__main__")


if __name__ == "__main__":
    main()
