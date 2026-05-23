#!/bin/bash
# One-time venv on $SCRATCH (pip install). Run inside a SLURM compute job, not on login nodes.
set -euo pipefail

: "${SCRATCH:?SCRATCH is not set — run this on an Athena compute node}"

VENV_DIR="${VENV_DIR:-${SCRATCH}/venv-ray}"

module load PyTorch-Geometric/2.5.1 2>/dev/null || true

python3 -m venv "$VENV_DIR"
# shellcheck source=/dev/null
source "$VENV_DIR/bin/activate"

pip install --upgrade pip
pip install "ray[tune]>=2.49" pydantic pyyaml torch torchvision

echo "Virtualenv ready: $VENV_DIR"
echo "Activate with: source $VENV_DIR/bin/activate"
ray --version
