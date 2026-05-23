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

module load pytorch/1.10.0-foss-2021a-cuda-11.3.1
module load torchvision/0.11.1-foss-2021a-cuda-11.3.1-pytorch-1.10.0
source "${VENV_PATH:-${SCRATCH}/venv-ray}/bin/activate"

export RAY_TMPDIR="/tmp/ray-${USER}"
mkdir -p "$RAY_TMPDIR"
export RAY_BACKEND_LOG_LEVEL="${RAY_BACKEND_LOG_LEVEL:-error}"

nodes=$(scontrol show hostnames "$SLURM_JOB_NODELIST")
nodes_array=($nodes)
head_node=${nodes_array[0]}
port=6379
head_ip=$(srun --nodes=1 --ntasks=1 -w "$head_node" --cpu-bind=none \
  bash -c 'hostname -I | awk "{print \$1}"' | tr -d '[:space:]')
ip_head="${head_ip}:${port}"

echo "Head node: ${head_node}"
echo "IP Head: ${ip_head}"
echo "Nodes: ${nodes_array[*]}"
echo "Job started at: $(date -Is)"

ray_cluster_cleanup() {
  for node in "${nodes_array[@]}"; do
    srun --overlap --nodes=1 --ntasks=1 -w "$node" --cpu-bind=none \
      bash -c 'ray stop >/dev/null 2>&1' || true
  done
}
trap ray_cluster_cleanup EXIT

srun --nodes=1 --ntasks=1 -w "$head_node" --cpu-bind=none \
  ray start --head --node-ip-address="${head_ip}" --port="${port}" \
  --num-cpus="${SLURM_CPUS_PER_TASK}" \
  --num-gpus=0 \
  --temp-dir="${RAY_TMPDIR}" \
  --disable-usage-stats \
  --block &

sleep 30

for worker in "${nodes_array[@]:1}"; do
  srun --nodes=1 --ntasks=1 -w "$worker" --cpu-bind=none \
    ray start --address="${ip_head}" \
    --num-cpus="${SLURM_CPUS_PER_TASK}" \
    --num-gpus=0 \
    --temp-dir="${RAY_TMPDIR}" \
    --disable-usage-stats \
    --block &
  sleep 10
done

sleep 15

export RAY_ADDRESS="${ip_head}"
if [[ "$(hostname -s)" == "${head_node}" ]]; then
  python -u "$REPO_ROOT/scripts/run_tune.py" \
    --gpus-per-trial 0 \
    --cpus-per-trial 4 \
    --data-dir "${SCRATCH}/data/cifar10" \
    --storage-path "${SCRATCH}/ray_results"
else
  srun --overlap --nodes=1 --ntasks=1 -w "$head_node" --cpu-bind=none \
    env RAY_ADDRESS="${ip_head}" \
    python -u "$REPO_ROOT/scripts/run_tune.py" \
      --gpus-per-trial 0 \
      --cpus-per-trial 4 \
      --data-dir "${SCRATCH}/data/cifar10" \
      --storage-path "${SCRATCH}/ray_results"
fi

echo "Job finished at: $(date -Is)"
