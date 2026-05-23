#!/bin/bash -l
#SBATCH --job-name=ray-tune-gpu
#SBATCH --partition=plgrid-gpu-a100
#SBATCH --account=<GRANT>-gpu-a100
#SBATCH --nodes=2
#SBATCH --ntasks-per-node=1
#SBATCH --cpus-per-task=16
#SBATCH --mem=128000
#SBATCH --gres=gpu:1
#SBATCH --time=02:00:00
#SBATCH --output=slurm-ray-tune-gpu-%j.out
#SBATCH --error=slurm-ray-tune-gpu-%j.err

set -euo pipefail

REPO_ROOT="${SLURM_SUBMIT_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}"
cd "$REPO_ROOT"

module load PyTorch-Geometric/2.5.1
source "${VENV_PATH:-${HOME}/venv-ray}/bin/activate"

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
ray_num_gpus="${SLURM_GPUS_PER_TASK:-${SLURM_GPUS_ON_NODE:-1}}"

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
  --num-gpus="${ray_num_gpus}" \
  --temp-dir="${RAY_TMPDIR}" \
  --disable-usage-stats \
  --block &

sleep 30

for worker in "${nodes_array[@]:1}"; do
  srun --nodes=1 --ntasks=1 -w "$worker" --cpu-bind=none \
    ray start --address="${ip_head}" \
    --num-cpus="${SLURM_CPUS_PER_TASK}" \
    --num-gpus="${ray_num_gpus}" \
    --disable-usage-stats \
    --block &
  sleep 10
done

sleep 15

export RAY_ADDRESS="${ip_head}"
if [[ "$(hostname -s)" == "${head_node}" ]]; then
  python -u "$REPO_ROOT/scripts/run_tune.py" \
    --gpus-per-trial 1 \
    --cpus-per-trial 2 \
    --data-dir "${SCRATCH}/data/cifar10" \
    --storage-path "${SCRATCH}/ray_results"
else
  srun --overlap --nodes=1 --ntasks=1 -w "$head_node" --cpu-bind=none \
    env RAY_ADDRESS="${ip_head}" \
    python -u "$REPO_ROOT/scripts/run_tune.py" \
      --gpus-per-trial 1 \
      --cpus-per-trial 2 \
      --data-dir "${SCRATCH}/data/cifar10" \
      --storage-path "${SCRATCH}/ray_results"
fi

echo "Job finished at: $(date -Is)"
