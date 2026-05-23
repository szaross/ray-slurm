#!/bin/bash -l
#SBATCH --job-name=ray-verify
#SBATCH --partition=plgrid-gpu-a100
#SBATCH --account=<GRANT>-gpu-a100
#SBATCH --nodes=2
#SBATCH --ntasks-per-node=1
#SBATCH --cpus-per-task=16
#SBATCH --mem=128000
#SBATCH --gres=gpu:1
#SBATCH --time=00:30:00
#SBATCH --output=slurm-ray-verify-%j.out
#SBATCH --error=slurm-ray-verify-%j.err

set -euo pipefail

REPO_ROOT="${SLURM_SUBMIT_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}"
cd "$REPO_ROOT"

module load PyTorch-Geometric/2.5.1
source "${VENV_PATH:-${SCRATCH}/venv-ray}/bin/activate"

export RAY_TMPDIR="/tmp/ray-${USER}"
mkdir -p "$RAY_TMPDIR"

nodes=($(scontrol show hostnames "$SLURM_JOB_NODELIST"))
export ip_head="${nodes[0]}:6379"
echo "Ray head address: $ip_head"
echo "Nodes: ${nodes[*]}"

srun --nodes="$SLURM_JOB_NUM_NODES" --ntasks="$SLURM_JOB_NUM_NODES" \
  ray symmetric-run \
    --address "$ip_head" \
    --min-nodes "$SLURM_JOB_NUM_NODES" \
    --num-cpus="${SLURM_CPUS_PER_TASK}" \
    --num-gpus="${SLURM_GPUS_PER_TASK:-1}" \
    --temp-dir="$RAY_TMPDIR" \
  -- python -u "$REPO_ROOT/scripts/verify_cluster.py"
