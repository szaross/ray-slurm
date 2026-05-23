#!/bin/bash
# Download CIFAR-10 into $SCRATCH/data/cifar10 (run inside a compute job).
set -euo pipefail

export DATA_DIR="${DATA_DIR:-${SCRATCH:-$HOME}/data/cifar10}"
mkdir -p "$DATA_DIR"

if [[ -f "${BASH_SOURCE[0]:-}" ]]; then
  REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
else
  REPO_ROOT="$(pwd)"
fi

source "${VENV_DIR:-${SCRATCH:-$HOME}/venv-ray}/bin/activate" 2>/dev/null || true

python3 - <<PY
import os
import torchvision

data_dir = os.environ.get("DATA_DIR", "${DATA_DIR}")
os.makedirs(data_dir, exist_ok=True)
torchvision.datasets.CIFAR10(root=data_dir, train=True, download=True)
torchvision.datasets.CIFAR10(root=data_dir, train=False, download=True)
print("CIFAR-10 ready at", data_dir)
PY
