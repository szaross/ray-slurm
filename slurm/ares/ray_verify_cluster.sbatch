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

nodes=$(scontrol show hostnames "$SLURM_JOB_NODELIST")
nodes_array=($nodes)
head_node=${nodes_array[0]}
port=6379
ip_head=$head_node:$port
export ip_head
echo "IP Head: $ip_head"
echo "Nodes: ${nodes_array[*]}"

srun --nodes="$SLURM_JOB_NUM_NODES" --ntasks="$SLURM_JOB_NUM_NODES" --ntasks-per-node=1 \
  --cpu-bind=none \
  python -m ray.scripts.symmetric_run \
  --address "$ip_head" \
  --min-nodes "$SLURM_JOB_NUM_NODES" \
  --num-cpus="${SLURM_CPUS_PER_TASK}" \
  --num-gpus="${SLURM_GPUS_PER_TASK:-0}" \
  --temp-dir="${RAY_TMPDIR}" \
  -- \
  python -u "$REPO_ROOT/scripts/verify_cluster.py"
