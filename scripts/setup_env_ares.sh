#!/bin/bash
# One-time Ray venv on Ares: PyTorch/torchvision from modules, Ray from pip.
# Run inside an interactive CPU SLURM job on ares.cyfronet.pl (not the login node).
set -euo pipefail

VENV_DIR="${VENV_DIR:-${HOME}/venv-ray}"

# Paired modules from: module avail torch  (on Ares)
module load pytorch/1.10.0-foss-2021a-cuda-11.3.1
module load torchvision/0.11.1-foss-2021a-cuda-11.3.1-pytorch-1.10.0

python3 -m venv --system-site-packages "$VENV_DIR"
# shellcheck source=/dev/null
source "$VENV_DIR/bin/activate"

pip install --upgrade pip
pip install "ray[tune]>=2.49" pydantic pyyaml

python -c "import torch, torchvision, ray; print('torch', torch.__version__, 'torchvision', torchvision.__version__, 'ray', ray.__version__)"

echo "Ares venv ready: $VENV_DIR"
echo "Activate: source $VENV_DIR/bin/activate"
echo "In sbatch jobs, load the same pytorch/torchvision modules before activating the venv."
