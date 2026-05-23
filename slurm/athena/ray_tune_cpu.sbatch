#!/bin/bash -l
#SBATCH --job-name=ray-tune-cpu
#SBATCH --partition=plgrid-gpu-a100
#SBATCH --account=<GRANT>-gpu-a100
#SBATCH --nodes=2
#SBATCH --ntasks-per-node=1
#SBATCH --cpus-per-task=16
#SBATCH --mem=128000
#SBATCH --gres=gpu:1
#SBATCH --time=04:00:00
#SBATCH --output=slurm-ray-tune-cpu-%j.out
#SBATCH --error=slurm-ray-tune-cpu-%j.err

set -euo pipefail

REPO_ROOT="${SLURM_SUBMIT_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}"
cd "$REPO_ROOT"
# shellcheck source=ray_cluster.sh
source "${REPO_ROOT}/slurm/athena/ray_cluster.sh"

ray_cluster_env
export RAY_DEDUP_LOGS="${RAY_DEDUP_LOGS:-1}"
ray_cluster_init
ray_cluster_install_trap

echo "Job started at: $(date -Is)"
ray_cluster_start

ray_cluster_run_on_head python -u "$REPO_ROOT/scripts/run_tune.py" \
  --gpus-per-trial 0 \
  --cpus-per-trial 4 \
  --experiment-name cifar10_tune_lab_cpu \
  --data-dir "${SCRATCH}/data/cifar10" \
  --storage-path "${SCRATCH}/ray_results"

echo "Job finished at: $(date -Is)"
