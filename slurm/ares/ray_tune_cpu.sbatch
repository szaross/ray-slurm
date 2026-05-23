#!/bin/bash -l
#SBATCH --job-name=ray-tune-cpu
#SBATCH --partition=plgrid
#SBATCH --account=<GRANT>-cpu
#SBATCH --nodes=2
#SBATCH --ntasks-per-node=1
#SBATCH --cpus-per-task=24
#SBATCH --mem=92G
#SBATCH --time=04:00:00
#SBATCH --output=slurm-ray-tune-cpu-%j.out
#SBATCH --error=slurm-ray-tune-cpu-%j.err

set -euo pipefail

REPO_ROOT="${SLURM_SUBMIT_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}"
cd "$REPO_ROOT"

source "${VENV_PATH:-${HOME}/venv-ray}/bin/activate"

export RAY_TMPDIR="/tmp/ray-${USER}"
mkdir -p "$RAY_TMPDIR"
export RAY_SYMMETRIC_RUN_CLUSTER_WAIT_TIMEOUT="${RAY_SYMMETRIC_RUN_CLUSTER_WAIT_TIMEOUT:-120}"

nodes=$(scontrol show hostnames "$SLURM_JOB_NODELIST")
nodes_array=($nodes)
head_node=${nodes_array[0]}
port=6379
head_ip=$(srun --nodes=1 --ntasks=1 -w "$head_node" --cpu-bind=none \
  bash -c 'hostname -I | awk "{print \$1}"' | tr -d '[:space:]')
ip_head="${head_ip}:${port}"
export ip_head
echo "Head node: ${head_node}"
echo "IP Head: ${ip_head}"
echo "Nodes: ${nodes_array[*]}"
echo "Job started at: $(date -Is)"

srun --nodes="$SLURM_JOB_NUM_NODES" --ntasks="$SLURM_JOB_NUM_NODES" --ntasks-per-node=1 \
  --cpu-bind=none \
  python -m ray.scripts.symmetric_run \
  --address "$ip_head" \
  --min-nodes "$SLURM_JOB_NUM_NODES" \
  --num-cpus="${SLURM_CPUS_PER_TASK}" \
  --num-gpus="${SLURM_GPUS_PER_TASK:-0}" \
  --temp-dir="${RAY_TMPDIR}" \
  -- \
  python -u "$REPO_ROOT/scripts/run_tune.py" \
    --gpus-per-trial 0 \
    --cpus-per-trial 4 \
    --data-dir "${SCRATCH}/data/cifar10" \
    --storage-path "${SCRATCH}/ray_results"

echo "Job finished at: $(date -Is)"
