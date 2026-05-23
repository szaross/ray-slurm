#!/bin/bash
# One-time Ray venv on Ares: PyTorch/torchvision from modules, Ray from pip.
# Run inside an interactive CPU SLURM job on ares.cyfronet.pl (not the login node).
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
: "${SCRATCH:?SCRATCH is not set — run this on a compute node}"

VENV_DIR="${VENV_DIR:-${SCRATCH}/venv-ray}"

# Paired modules from: module avail torch  (on Ares)
module load pytorch/1.10.0-foss-2021a-cuda-11.3.1
module load torchvision/0.11.1-foss-2021a-cuda-11.3.1-pytorch-1.10.0

# Remove an old venv if Ray failed to import (protobuf conflict with system modules).
if [[ -d "$VENV_DIR" ]] && ! "$VENV_DIR/bin/python" -c "import ray" 2>/dev/null; then
  echo "Removing broken venv at $VENV_DIR (run again after this)..."
  rm -rf "$VENV_DIR"
fi

python3 -m venv --system-site-packages "$VENV_DIR"
# shellcheck source=/dev/null
source "$VENV_DIR/bin/activate"

pip install --upgrade pip
# Pin protobuf<5: system modules ship protobuf 3.17; Ray breaks with 3.17 or mixed 6.x.
pip install -r "$REPO_ROOT/requirements-ares.txt"

python -c "import google.protobuf; print('protobuf', google.protobuf.__version__)"
python -c "import torch, torchvision, ray; print('torch', torch.__version__, 'torchvision', torchvision.__version__, 'ray', ray.__version__)"

echo "Ares venv ready: $VENV_DIR"
echo "Activate: source $VENV_DIR/bin/activate"
echo "Always load pytorch+torchvision modules before activating (see slurm/ares/*.sbatch)."
