# Shared Ray cluster helpers for Athena sbatch jobs. Source from sbatch; do not submit.
# Expects: REPO_ROOT set, cwd at repo root, SLURM_JOB_NODELIST available.

ray_cluster_env() {
  module load PyTorch-Geometric/2.5.1
  # shellcheck source=/dev/null
  source "${VENV_PATH:-${SCRATCH}/venv-ray}/bin/activate"
  export RAY_TMPDIR="/tmp/ray-${USER}"
  mkdir -p "$RAY_TMPDIR"
  export RAY_BACKEND_LOG_LEVEL="${RAY_BACKEND_LOG_LEVEL:-error}"
}

ray_cluster_start_log() {
  echo "${RAY_TMPDIR}/ray-start-${SLURM_JOB_ID}-${1}.log"
}

ray_cluster_init() {
  local nodes
  nodes=$(scontrol show hostnames "$SLURM_JOB_NODELIST")
  nodes_array=($nodes)
  head_node=${nodes_array[0]}
  port=6379
  head_ip=$(srun --nodes=1 --ntasks=1 -w "$head_node" --cpu-bind=none \
    bash -c 'hostname -I | awk "{print \$1}"' | tr -d '[:space:]')
  ip_head="${head_ip}:${port}"
  ray_num_gpus="${SLURM_GPUS_PER_TASK:-${SLURM_GPUS_ON_NODE:-1}}"
  export RAY_ADDRESS="${ip_head}"
  echo "RAY_ADDRESS=${ip_head} nodes=${nodes_array[*]} head=${head_node}"
}

ray_cluster_cleanup() {
  for node in "${nodes_array[@]}"; do
    srun --overlap --nodes=1 --ntasks=1 -w "$node" --cpu-bind=none \
      bash -c 'ray stop >/dev/null 2>&1' || true
  done
}

ray_cluster_install_trap() {
  trap ray_cluster_cleanup EXIT
}

ray_cluster_start() {
  local log node
  # RAY_TMPDIR must exist on each node (batch mkdir only covers the head).
  for node in "${nodes_array[@]}"; do
    srun --nodes=1 --ntasks=1 -w "$node" --cpu-bind=none \
      bash -c "mkdir -p '${RAY_TMPDIR}'" || true
  done

  log=$(ray_cluster_start_log "$head_node")
  srun --nodes=1 --ntasks=1 -w "$head_node" --cpu-bind=none \
    bash -c "mkdir -p '${RAY_TMPDIR}' && ray start --head --node-ip-address='${head_ip}' --port='${port}' \
      --num-cpus='${SLURM_CPUS_PER_TASK}' --num-gpus='${ray_num_gpus}' \
      --temp-dir='${RAY_TMPDIR}' --disable-usage-stats --block \
      >>'${log}' 2>&1" &
  sleep 30
  for worker in "${nodes_array[@]:1}"; do
    log=$(ray_cluster_start_log "$worker")
    srun --nodes=1 --ntasks=1 -w "$worker" --cpu-bind=none \
      bash -c "mkdir -p '${RAY_TMPDIR}' && ray start --address='${ip_head}' \
        --num-cpus='${SLURM_CPUS_PER_TASK}' --num-gpus='${ray_num_gpus}' \
        --temp-dir='${RAY_TMPDIR}' --disable-usage-stats --block \
        >>'${log}' 2>&1" &
    sleep 10
  done
  sleep 15
}

# Run a command on the Ray head (batch node or srun --overlap). RAY_ADDRESS must be set.
ray_cluster_run_on_head() {
  if [[ "$(hostname -s)" == "${head_node}" ]]; then
    "$@"
  else
    srun --overlap --nodes=1 --ntasks=1 -w "$head_node" --cpu-bind=none \
      env RAY_ADDRESS="${ip_head}" "$@"
  fi
}
