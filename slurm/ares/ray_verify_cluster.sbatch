#!/bin/bash -l
#SBATCH --job-name=ray-verify-cpu
#SBATCH --partition=plgrid-testing
#SBATCH --account=<GRANT>-cpu
#SBATCH --nodes=2
#SBATCH --ntasks-per-node=1
#SBATCH --cpus-per-task=24
#SBATCH --mem=92G
#SBATCH --time=00:30:00
#SBATCH --output=slurm-ray-verify-cpu-%j.out
#SBATCH --error=slurm-ray-verify-cpu-%j.err

set -euo pipefail

REPO_ROOT="${SLURM_SUBMIT_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}"
cd "$REPO_ROOT"

source "${VENV_PATH:-${HOME}/venv-ray}/bin/activate"

export RAY_TMPDIR="/tmp/ray-${USER}"
mkdir -p "$RAY_TMPDIR"

nodes=($(scontrol show hostnames "$SLURM_JOB_NODELIST"))
export ip_head="${nodes[0]}:6379"
echo "Ray head address: $ip_head"

srun --nodes="$SLURM_JOB_NUM_NODES" --ntasks="$SLURM_JOB_NUM_NODES" \
  ray symmetric-run \
    --address "$ip_head" \
    --min-nodes "$SLURM_JOB_NUM_NODES" \
    --num-cpus="${SLURM_CPUS_PER_TASK}" \
    --num-gpus=0 \
    --temp-dir="$RAY_TMPDIR" \
  -- python -u "$REPO_ROOT/scripts/verify_cluster.py"
