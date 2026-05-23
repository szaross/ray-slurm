#!/bin/bash
# One-time environment setup (run inside an interactive SLURM job, not on login nodes).
set -euo pipefail

VENV_DIR="${VENV_DIR:-${SCRATCH:-$HOME}/venv-ray}"

python3 -m venv "$VENV_DIR"
# shellcheck source=/dev/null
source "$VENV_DIR/bin/activate"

pip install --upgrade pip
pip install "ray[tune]>=2.49" pyyaml torchvision  # symmetric-run needs 2.49+

echo "Virtualenv ready: $VENV_DIR"
echo "Activate with: source $VENV_DIR/bin/activate"
ray --version
