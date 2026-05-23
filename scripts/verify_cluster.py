#!/usr/bin/env python3
"""Sanity-check Ray cluster resources before running Tune."""

from __future__ import annotations

import json
import os
import sys

# Quieter Ray client when connecting to a cluster with num_gpus=0 on workers.
os.environ.setdefault("RAY_ACCEL_ENV_VAR_OVERRIDE_ON_ZERO", "0")

import ray


def main() -> int:
    connected_here = False
    if not ray.is_initialized():
        address = os.environ.get("RAY_ADDRESS", "auto")
        ray.init(address=address, logging_level="error")
        connected_here = True

    exit_code = 0
    try:
        resources = ray.cluster_resources()
        nodes = ray.nodes()
        alive = [n for n in nodes if n.get("Alive")]

        print("=== Ray cluster verification ===")
        print(f"Alive nodes: {len(alive)}")
        print(
            "Cluster resources:",
            json.dumps(
                {k: v for k, v in resources.items() if not k.startswith("node:")},
                indent=2,
                sort_keys=True,
            ),
        )
        print(f"Nodes: {[n.get('NodeManagerAddress') for n in alive]}")

        cpu = resources.get("CPU", 0)
        gpu = resources.get("GPU", 0)
        if cpu <= 0:
            print("ERROR: no CPUs visible to Ray.", file=sys.stderr)
            exit_code = 1
        else:
            print("\nOK: Ray sees at least one node with CPUs.")
            if gpu == 0:
                print("NOTE: GPU count is 0 (expected on Ares CPU runs).")
    finally:
        if connected_here:
            ray.shutdown()

    return exit_code


if __name__ == "__main__":
    sys.exit(main())
