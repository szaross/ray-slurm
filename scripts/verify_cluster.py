#!/usr/bin/env python3
"""Sanity-check Ray cluster resources before running Tune."""

from __future__ import annotations

import json
import sys

import ray


def main() -> int:
    if not ray.is_initialized():
        ray.init(address="auto")

    resources = ray.cluster_resources()
    nodes = ray.nodes()
    alive = [n for n in nodes if n.get("Alive")]

    print("=== Ray cluster verification ===")
    print(f"Alive nodes: {len(alive)}")
    print("Cluster resources:", json.dumps(resources, indent=2, sort_keys=True))

    for i, node in enumerate(alive):
        res = node.get("Resources", {})
        print(f"\nNode {i}: {node.get('NodeManagerAddress', '?')}")
        print(f"  Resources: {res}")

    cpu = resources.get("CPU", 0)
    gpu = resources.get("GPU", 0)
    if cpu <= 0:
        print("ERROR: no CPUs visible to Ray.", file=sys.stderr)
        return 1

    print("\nOK: Ray sees at least one node with CPUs.")
    if gpu == 0:
        print("NOTE: GPU count is 0 (expected on Ares CPU runs).")
    return 0


if __name__ == "__main__":
    sys.exit(main())
