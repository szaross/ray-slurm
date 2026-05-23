# Lab: Ray on SLURM (Athena)

## Overview

You will:

1. Configure and run a **multi-node Ray cluster** under SLURM on [Athena](https://docs.hpc.cyfronet.pl/supercomputers/athena/).
2. Run two **Ray Tune** hyperparameter sweeps on that cluster: **GPU trials** and **CPU trials**.
3. Compare results in a short report.

The tuning workload is provided in [`scripts/run_tune.py`](../scripts/run_tune.py). Your main task is **SLURM + Ray cluster setup**, not writing the tuner.

| You configure | Provided for you |
|---------------|------------------|
| `#SBATCH` account, nodes, resources in [`slurm/athena/ray_verify_cluster.sbatch`](../slurm/athena/ray_verify_cluster.sbatch) | CIFAR-10 CNN + search space |
| Multi-node `ray start` (via shared [`slurm/athena/ray_cluster.sh`](../slurm/athena/ray_cluster.sh)) | [`scripts/run_tune.py`](../scripts/run_tune.py), Tune schedulers |
| Submit verify + tune jobs | GPU/CPU tune sbatch templates |

## Before you start

- PLGrid grant with Athena GPU access (`<GRANT>-gpu-a100`).
- SSH: `athena.cyfronet.pl`
- Clone this repo (e.g. `git clone … $HOME/ray-slurm`).
- Replace `<GRANT>` in all `slurm/athena/*.sbatch` files.

**Where to run commands**

| Command | Run on |
|---------|--------|
| `sbatch slurm/athena/*.sbatch` | **Login node** (after `ssh athena.cyfronet.pl`) |
| `bash scripts/setup_env.sh`, `download_cifar.sh`, `srun … --pty` | **Compute node** (inside an allocated job) |

From the login node: `cd $HOME/ray-slurm` before every `sbatch`. Do **not** submit `sbatch` from inside an interactive `srun` session.

---

## Setup (compute node)

Run once inside a GPU compute job (`srun … --pty` or a short batch job).

### Virtualenv on `$SCRATCH`

```bash
cd $HOME/ray-slurm
bash scripts/setup_env.sh
source $SCRATCH/venv-ray/bin/activate
python -c "import torch, ray; print('ok')"
```

The venv lives at **`$SCRATCH/venv-ray`** (not `$HOME`). If you created `$HOME/venv-ray` earlier, remove it and rerun `setup_env.sh`.

### Ray session directory

```bash
export RAY_TMPDIR="/tmp/ray-${USER}"
mkdir -p "$RAY_TMPDIR"
```

Batch scripts set this automatically; use the same path in interactive tests.

### CIFAR-10 data

```bash
source $SCRATCH/venv-ray/bin/activate
bash scripts/download_cifar.sh
```

Data lands in `$SCRATCH/data/cifar10`.

---

## Optional: single-node warm-up

Allocate one node and check Ray locally before the multi-node exercise:

```bash
srun -p plgrid-gpu-a100 -N 1 -n 1 --cpus-per-task=16 --mem=128000 \
  -A <GRANT>-gpu-a100 --gres=gpu:1 --time=01:00:00 --pty /bin/bash -l
```

```bash
module load PyTorch-Geometric/2.5.1
source $SCRATCH/venv-ray/bin/activate
export RAY_TMPDIR="/tmp/ray-${USER}"
mkdir -p "$RAY_TMPDIR"
ray start --head --num-gpus=1 --temp-dir="$RAY_TMPDIR"
python scripts/verify_cluster.py
ray stop
```

---

## Main exercise: multi-node Ray

1. Edit [`slurm/athena/ray_verify_cluster.sbatch`](../slurm/athena/ray_verify_cluster.sbatch): set `#SBATCH --account=<GRANT>-gpu-a100` and check `nodes`, `cpus-per-task`, `gres` match your goals (default: 2 nodes, 16 CPUs, 1 GPU per node).
2. Submit from the login node:

   ```bash
   sbatch slurm/athena/ray_verify_cluster.sbatch
   ```

3. Inspect `slurm-ray-verify-<jobid>.out`. You should see:
   - `RAY_ADDRESS=172.23.x.x:6379` (head **IP**, not short hostname)
   - `Alive nodes: 2`
   - Cluster resources listing CPUs and GPUs

**Troubleshooting**

- Workers stuck at 1/2 nodes: `--address` must use the head compute IP from the log.
- Job hangs at verify: the template runs Python on the batch/head node (not a second blocking `srun` on an occupied head).
- Ray daemon details: see `$RAY_TMPDIR/ray-start-<jobid>-<node>.log` on the nodes if the cluster fails to start.

**Deliverable checkpoint:** your edited verify sbatch and log excerpts showing two alive nodes.

---

## GPU hyperparameter sweep

Uses the same 2-node layout; Tune requests **1 GPU per trial**.

```bash
sbatch slurm/athena/ray_tune_gpu.sbatch
```

- Logs: `slurm-ray-tune-gpu-<jobid>.out` (Tune trial progress + `=== Sweep finished ===` summary)
- Results: `$SCRATCH/ray_results/cifar10_tune_lab_gpu/`

---

## CPU hyperparameter sweep

Same cluster and Athena policy: jobs still use `#SBATCH --gres=gpu:1`, but Tune uses **`--gpus-per-trial 0`** (training on CPU).

```bash
sbatch slurm/athena/ray_tune_cpu.sbatch
```

- Results: `$SCRATCH/ray_results/cifar10_tune_lab_cpu/`

| Script | `gpus-per-trial` | `cpus-per-trial` | Results folder |
|--------|------------------|------------------|----------------|
| `ray_tune_gpu.sbatch` | 1 | 2 | `cifar10_tune_lab_gpu` |
| `ray_tune_cpu.sbatch` | 0 | 4 | `cifar10_tune_lab_cpu` |

Compare both sweeps in your report (wall time, metrics, and what Ray/Tune printed).

---

## Report

### Comparison table

| Metric | GPU sweep | CPU sweep |
|--------|-----------|-----------|
| SLURM nodes | | |
| `#SBATCH --gres` | | |
| `gpus-per-trial` / `cpus-per-trial` | | |
| `num_samples` | | |
| Sweep wall time (minutes) | | |
| Best validation `loss` | | |
| Best validation `accuracy` | | |
| Ray cluster CPUs / GPUs (from verify or Tune log) | | |

### Short answers (½–1 page)

1. Why does the CPU sweep still request a GPU in SLURM on Athena?
2. What limits how many Tune trials run **in parallel** on your cluster?
3. What happens if `--num-cpus` passed to `ray start` is **larger** than `SLURM_CPUS_PER_TASK`?

### Deliverables

1. Modified `ray_verify_cluster.sbatch` with your grant.
2. Log excerpts: verify output + both sweep summaries (`=== Sweep finished ===`).
3. Completed table and short answers.

---

## References

- [Ray on SLURM](https://docs.ray.io/en/latest/cluster/vms/user-guides/community/slurm.html)
- [PyTorch + Ray Tune CIFAR tutorial](https://docs.pytorch.org/tutorials/beginner/hyperparameter_tuning_tutorial.html)
- [Athena documentation](https://docs.hpc.cyfronet.pl/supercomputers/athena/)
