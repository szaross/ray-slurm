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

ray_cluster_cleanup() {
  for node in "${nodes_array[@]}"; do
    echo "Stopping Ray on ${node}..."
    srun --nodes=1 --ntasks=1 -w "$node" --cpu-bind=none ray stop || true
  done
}
trap ray_cluster_cleanup EXIT

echo "Starting Ray head on ${head_node}..."
srun --nodes=1 --ntasks=1 -w "$head_node" --cpu-bind=none \
  ray start --head --node-ip-address="${head_ip}" --port="${port}" \
  --num-cpus="${SLURM_CPUS_PER_TASK}" \
  --num-gpus="${ray_num_gpus}" \
  --temp-dir="${RAY_TMPDIR}" \
  --disable-usage-stats \
  --block &

echo "Waiting for head GCS..."
sleep 30

for worker in "${nodes_array[@]:1}"; do
  echo "Starting Ray worker on ${worker}..."
  srun --nodes=1 --ntasks=1 -w "$worker" --cpu-bind=none \
    ray start --address="${ip_head}" \
    --num-cpus="${SLURM_CPUS_PER_TASK}" \
    --num-gpus="${ray_num_gpus}" \
    --temp-dir="${RAY_TMPDIR}" \
    --disable-usage-stats \
    --block &
  sleep 10
done

echo "Waiting for workers to register..."
sleep 15

echo "Ray status on head:"
srun --nodes=1 --ntasks=1 -w "$head_node" --cpu-bind=none \
  env RAY_ADDRESS="${ip_head}" ray status || true

echo "Running verify_cluster.py on ${head_node}..."
srun --nodes=1 --ntasks=1 -w "$head_node" --cpu-bind=none \
  env RAY_ADDRESS="${ip_head}" \
  python -u "$REPO_ROOT/scripts/verify_cluster.py"

echo "Verify job step finished at: $(date -Is)"
