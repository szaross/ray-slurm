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

# Getting the node names (Ray SLURM docs)
nodes=$(scontrol show hostnames "$SLURM_JOB_NODELIST")
nodes_array=($nodes)
head_node=${nodes_array[0]}
port=6379
ip_head=$head_node:$port
export ip_head
echo "IP Head: $ip_head"
echo "Nodes: ${nodes_array[*]}"

# Start Ray cluster using symmetric-run on all nodes.
# Symmetric run will automatically start Ray on all nodes and run the script ONLY the head node.
# Use the '--' separator to separate Ray arguments and the entrypoint command.
# The --min-nodes argument ensures all nodes join before running the script.
#
# All nodes (including head and workers) will execute this block.
# The entrypoint will only run on the head node.
srun --nodes="$SLURM_JOB_NUM_NODES" --ntasks="$SLURM_JOB_NUM_NODES" \
  ray symmetric-run \
  --address "$ip_head" \
  --min-nodes "$SLURM_JOB_NUM_NODES" \
  --num-cpus="${SLURM_CPUS_PER_TASK}" \
  --num-gpus="${SLURM_GPUS_PER_TASK}" \
  --temp-dir="${RAY_TMPDIR}" \
  -- \
  python -u "$REPO_ROOT/scripts/verify_cluster.py"
