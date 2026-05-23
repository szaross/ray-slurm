#!/bin/bash
# One-time venv for Athena (pip install). On Ares use scripts/setup_env_ares.sh (PyTorch modules).
# Run inside an interactive SLURM compute job, not on login nodes.
set -euo pipefail

VENV_DIR="${VENV_DIR:-${HOME}/venv-ray}"

module load PyTorch-Geometric/2.5.1 2>/dev/null || true

python3 -m venv "$VENV_DIR"
# shellcheck source=/dev/null
source "$VENV_DIR/bin/activate"

pip install --upgrade pip
pip install "ray[tune]>=2.49" pydantic pyyaml torch torchvision

echo "Virtualenv ready: $VENV_DIR"
echo "Activate with: source $VENV_DIR/bin/activate"
ray --version
