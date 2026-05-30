# Instructor notes — Ray + SLURM lab

## Overview

Students configure **multi-node Ray on Athena** ([`slurm/athena/ray_verify_cluster.sbatch`](../slurm/athena/ray_verify_cluster.sbatch) + shared [`slurm/athena/ray_cluster.sh`](../slurm/athena/ray_cluster.sh)), then run [`scripts/run_tune.py`](../scripts/run_tune.py) twice:

| Run | SLURM template | Tune resources | Results dir |
|-----|----------------|----------------|-------------|
| GPU | `ray_tune_gpu.sbatch` | `--gpus-per-trial 1`, `--cpus-per-trial 2` | `cifar10_tune_lab_gpu` |
| CPU | `ray_tune_cpu.sbatch` | `--gpus-per-trial 0`, `--cpus-per-trial 4` | `cifar10_tune_lab_cpu` |

Both use `#SBATCH --gres=gpu:1` (Athena policy). Training device for CPU sweep is forced to CPU in `run_tune.py` when `gpus_per_trial=0`.

Defaults: [`config/lab_defaults.yaml`](../config/lab_defaults.yaml) — 12 trials, 3 epochs.

## Expected runtime (2 nodes, pilot on grant)

| Job | Rough wall time |
|-----|-----------------|
| Verify | 5–15 min |
| GPU tune | ~3–30 min (depends on parallelism + load) |
| CPU tune | ~2–15 min sweep + cluster overhead |

Pilot with 12 samples / 3 epochs: CPU sweep wall ~1–2 min, GPU sweep wall can be **longer** than CPU despite faster per-trial GPU training (see answer key).

## Answer key (do not put in student lab)

**Wall time vs per-trial time:** On 2×1 GPU nodes, GPU trials cap at **~2 parallel** runs (`gpus-per-trial=1`). CPU trials with `cpus-per-trial=4` on 32 cluster CPUs allow **~8 parallel** runs. So total sweep wall time can be **shorter on CPU** even when each GPU trial’s `time_total_s` is lower. Students should use Tune output (`time_total_s`, resource usage lines) and short answer #2.

**Short answers (expected points):**

1. Athena batch policy requires GPU allocation; SLURM GRES ≠ Tune using a GPU (`--gpus-per-trial 0`).
2. `min(cluster_CPUs / cpus_per_trial, cluster_GPUs / gpus_per_trial)` (and memory); Ray Tune scheduling.
3. Oversubscription / misleading `ray status`; workers may fail or contend with SLURM cgroups.

## Grading rubric (100%)

| Criterion | Weight | Pass indicators |
|-----------|--------|-----------------|
| Multi-node Ray | 50% | Correct `#SBATCH`; verify shows N nodes; head IP in log |
| Jobs + artifacts | 30% | GPU + CPU logs; results under `$SCRATCH/ray_results` |
| Analysis | 20% | Table + reasonable answers (incl. parallelism for Q2) |

## Common failures

| Symptom | Likely cause | Fix |
|---------|--------------|-----|
| `sbatch` from compute node | Wrong shell | Login node only; `cd` to repo |
| `AF_UNIX path too long` | Deep Ray temp path | `RAY_TMPDIR=/tmp/ray-$USER` |
| Workers never join | Hostname vs IP | Head compute IP in `RAY_ADDRESS` |
| `SLURM_GPUS_PER_TASK` unbound | `set -u` on Cyfronet | `${SLURM_GPUS_PER_TASK:-${SLURM_GPUS_ON_NODE:-1}}` in `ray_cluster.sh` |
| CPU bind errors | Nested `srun` | `--cpu-bind=none` in `ray_cluster.sh` |
| Hang at verify | Second `srun` on head | `ray_cluster_run_on_head` |
| Cluster start failures | GCS / network | `cat $RAY_TMPDIR/ray-start-<jobid>-<node>.log` on that node |
| Workers fail, `Alive nodes: 1` | `$RAY_TMPDIR` missing on workers | `mkdir -p` on each node before `ray start` (see `ray_cluster.sh`) |
| `pydantic` missing | venv | Re-run `setup_env.sh` |
| CPU trials on GPU | Old `run_tune.py` | `gpus_per_trial` passed into `train_cifar` |

## HPC validation checklist

1. [ ] Single-node `ray start` + `verify_cluster.py`
2. [ ] `sbatch slurm/athena/ray_verify_cluster.sbatch` — 2 nodes alive
3. [ ] `sbatch slurm/athena/ray_tune_gpu.sbatch` — completes
4. [ ] `sbatch slurm/athena/ray_tune_cpu.sbatch` — CPU training, completes
5. [ ] Tune `.out` is mostly trial progress + sweep summary; daemon logs in `$RAY_TMPDIR/ray-start-*.log`

## Environment

- `module load PyTorch-Geometric/2.5.1` + `$SCRATCH/venv-ray` via `scripts/setup_env.sh` on a compute node
- Copy artifacts from `$SCRATCH` before scratch cleanup

## Customization

- Shorter lab: `num_samples: 6`, `max_epochs: 2` in `lab_defaults.yaml`
- Longer wall limit on tune sbatch if grants are slow

## References

- [task.md](../task.md)
- [docs/LAB.md](LAB.md)
