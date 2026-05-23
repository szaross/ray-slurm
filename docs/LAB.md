# Lab: Ray on SLURM (Athena — GPU vs CPU tuning)

## Objectives

After this lab you should be able to:

1. Start and verify a **multi-node Ray cluster** under SLURM on **Athena**.
2. Run a provided **Ray Tune** hyperparameter sweep with **GPU trials** and **CPU trials** on the same cluster.
3. Compare wall-clock time, throughput, and best validation metrics between the two runs.

You do **not** need to implement hyperparameter tuning logic—the workload is in [`scripts/run_tune.py`](../scripts/run_tune.py).

## Prerequisites

- Active [PLGrid](https://www.plgrid.pl/) grant with access to **Athena** (`-gpu-a100`).
- SSH: `athena.cyfronet.pl`.
- Clone this repository to `$HOME` or `$SCRATCH`.
- Read [Athena documentation](https://docs.hpc.cyfronet.pl/supercomputers/athena/).

Replace `<GRANT>` in SLURM scripts with your grant name (e.g. `plg12345` → account `plg12345-gpu-a100`).

---

## Part 0 — Environment setup

Run inside **interactive compute jobs** on Athena, not on login nodes.

### 0.1 Python virtualenv (on `$SCRATCH`)

The venv is created on **`$SCRATCH/venv-ray`**, not in `$HOME` (faster I/O, avoids home quota).

```bash
cd $HOME/ray-slurm   # repo can stay in $HOME; venv goes to scratch
bash scripts/setup_env.sh
source $SCRATCH/venv-ray/bin/activate
python -c "import torch, ray; print('ok')"
```

If you previously used `$HOME/venv-ray`, delete it and rerun `setup_env.sh` so everything uses scratch.

### 0.2 Ray temp directory

```bash
export RAY_TMPDIR="/tmp/ray-${USER}"
mkdir -p "$RAY_TMPDIR"
```

### 0.3 Download CIFAR-10

```bash
source $SCRATCH/venv-ray/bin/activate
bash scripts/download_cifar.sh
```

---

## Part 1 — Single-node Ray on Athena (warm-up)

```bash
srun -p plgrid-gpu-a100 -N 1 -n 1 --cpus-per-task=16 --mem=128000 \
  -A <GRANT>-gpu-a100 --gres=gpu:1 --time=01:00:00 --pty /bin/bash -l
```

On the compute node:

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

## Part 2 — Multi-node Ray on Athena (main exercise)

Configure and submit [`slurm/athena/ray_verify_cluster.sbatch`](../slurm/athena/ray_verify_cluster.sbatch) (set `#SBATCH --account=<GRANT>-gpu-a100`).

```bash
sbatch slurm/athena/ray_verify_cluster.sbatch
```

Confirm in `slurm-ray-verify-<jobid>.out`: **`Alive nodes: 2`**.

Key ideas: head **IP** (`172.23.x.x:6379`), staggered `ray start`, verify runs on the **batch node** (not a second competing `srun`).

---

## Part 3 — GPU hyperparameter sweep

Same cluster layout as Part 2; trials use **one GPU each**.

```bash
sbatch slurm/athena/ray_tune_gpu.sbatch
```

Results: `$SCRATCH/ray_results/cifar10_tune_lab_gpu/`

```bash
tail -f slurm-ray-tune-gpu-<jobid>.out
```

---

## Part 4 — CPU hyperparameter sweep (also on Athena)

Athena jobs must **request a GPU** in SLURM (`#SBATCH --gres=gpu:1`). The CPU comparison still runs on Athena: Ray sees the GPUs, but Tune is told to use **CPU only** (`--gpus-per-trial 0`).

```bash
sbatch slurm/athena/ray_tune_cpu.sbatch
```

Results: `$SCRATCH/ray_results/cifar10_tune_lab_cpu/`

Expect **longer** wall time than Part 3. The cluster setup (nodes, `ray start`) is the same; only the Tune resource flags change.

| Script | Tune GPUs per trial | Tune CPUs per trial | Results folder |
|--------|---------------------|---------------------|----------------|
| `ray_tune_gpu.sbatch` | 1 | 2 | `cifar10_tune_lab_gpu` |
| `ray_tune_cpu.sbatch` | 0 | 4 | `cifar10_tune_lab_cpu` |

---

## Part 5 — Analysis and deliverables

### Comparison table

| Metric | GPU sweep | CPU sweep |
|--------|-----------|-----------|
| SLURM nodes | | |
| `#SBATCH --gres` | | |
| `gpus-per-trial` / `cpus-per-trial` | | |
| `num_samples` | | |
| Wall time (minutes) | | |
| Best validation `loss` | | |
| Best validation `accuracy` | | |
| Ray cluster `CPU` / `GPU` | | |

### Short answers (½–1 page)

1. Why do we still use `#SBATCH --gres=gpu:1` for the CPU sweep on Athena?
2. What limits how many Tune trials run in parallel on your cluster?
3. What happens if `--num-cpus` passed to `ray start` is **larger** than `SLURM_CPUS_PER_TASK`?

### Deliverables

1. Your modified `ray_verify_cluster.sbatch` with grant filled in.
2. `slurm-*.out` excerpts: verify output + both tune summaries.
3. Completed comparison table and short answers.

---

## References

- [Ray on SLURM](https://docs.ray.io/en/latest/cluster/vms/user-guides/community/slurm.html)
- [PyTorch + Ray Tune CIFAR tutorial](https://docs.pytorch.org/tutorials/beginner/hyperparameter_tuning_tutorial.html)
- [Athena documentation](https://docs.hpc.cyfronet.pl/supercomputers/athena/)
