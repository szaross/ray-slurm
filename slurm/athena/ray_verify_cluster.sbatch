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
# shellcheck source=ray_cluster.sh
source "${REPO_ROOT}/slurm/athena/ray_cluster.sh"

ray_cluster_env
ray_cluster_init
ray_cluster_install_trap
ray_cluster_start

echo "Running verify_cluster.py..."
ray_cluster_run_on_head python -u "$REPO_ROOT/scripts/verify_cluster.py"
echo "Verify finished at: $(date -Is)"
