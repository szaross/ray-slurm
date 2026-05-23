# Lab: Ray on SLURM (Athena GPU vs Ares CPU)

## Objectives

After this lab you should be able to:

1. Start and verify a **multi-node Ray cluster** under SLURM on **Athena**.
2. Run a provided **Ray Tune** hyperparameter sweep on GPUs (Athena) and CPUs (Ares).
3. Compare wall-clock time, throughput, and best validation metrics between the two runs.

You do **not** need to implement hyperparameter tuning logic—the workload is in [`scripts/run_tune.py`](../scripts/run_tune.py).

## Prerequisites

- Active [PLGrid](https://www.plgrid.pl/) grant with access to **Athena** (`-gpu-a100`) and **Ares** (`-cpu`).
- SSH: `athena.cyfronet.pl`, `ares.cyfronet.pl`.
- Clone this repository to `$HOME` or `$SCRATCH` (home is shared across Cyfronet systems).
- Read [Athena](https://docs.hpc.cyfronet.pl/supercomputers/athena/) and [Ares](https://docs.hpc.cyfronet.pl/supercomputers/ares/) documentation.

Replace `<GRANT>` in all SLURM scripts with your grant name (e.g. `plg12345` → account `plg12345-gpu-a100` on Athena).

---

## Part 0 — Environment setup

Run these steps **inside interactive compute jobs**, not on login nodes.

### 0.1 Create Python virtualenv

On Athena (interactive GPU job, see Part 1.1):

```bash
cd $HOME/ray-slurm   # or your clone path
bash scripts/setup_env.sh
```

On Ares, if PyTorch is not available via modules, use the same venv in `$HOME/venv-ray` (created on Athena or via `setup_env.sh` on an Ares CPU job with `pip install torch torchvision`).

### 0.2 Ray version and temp directory

```bash
source ${SCRATCH}/venv-ray/bin/activate   # or $HOME/venv-ray
ray --version    # Ray 2.x
```

Ray’s default session path under deep `$SCRATCH` trees can exceed the Unix socket path limit (~107 bytes). Always use a **short** temp directory:

```bash
export RAY_TMPDIR="/tmp/ray-${USER}"
mkdir -p "$RAY_TMPDIR"
```

SLURM templates pass `--temp-dir="$RAY_TMPDIR"` to Ray.

### 0.3 Download CIFAR-10

Inside a compute job:

```bash
export DATA_DIR="${SCRATCH}/data/cifar10"
bash scripts/download_cifar.sh
```

---

## Part 1 — Single-node Ray on Athena (warm-up)

Request one GPU node (adjust `<GRANT>`):

```bash
srun -p plgrid-gpu-a100 -N 1 -n 1 --cpus-per-task=16 --mem=128000 \
  -A <GRANT>-gpu-a100 --gres=gpu:1 --time=01:00:00 --pty /bin/bash -l
```

On the compute node:

```bash
module load PyTorch-Geometric/2.5.1
source ${SCRATCH}/venv-ray/bin/activate
export RAY_TMPDIR="/tmp/ray-${USER}"
mkdir -p "$RAY_TMPDIR"

ray start --head --num-gpus=1 --temp-dir="$RAY_TMPDIR"
ray status
python scripts/verify_cluster.py
ray stop
```

**Checkpoint:** Paste `ray status` output showing 1 node and 1 GPU.

---

## Part 2 — Multi-node Ray on Athena (main exercise)

This is the core graded task: configure SLURM so Ray spans **multiple nodes**.

### 2.1 Understand the template

Open [`slurm/athena/ray_verify_cluster.sbatch`](../slurm/athena/ray_verify_cluster.sbatch) — multi-node startup uses `ray start --head` on the first node, `ray start --address=...` on workers (see [Ray SLURM guide](https://docs.ray.io/en/latest/cluster/vms/user-guides/community/slurm.html)), then runs Python on the head only.

| Setting | Why it matters |
|--------|----------------|
| `#SBATCH --nodes=N` | Number of machines in the Ray cluster |
| `#SBATCH --ntasks-per-node=1` | One `srun` task per node |
| `#SBATCH --gres=gpu:1` | GPUs per node (Athena requires GPU jobs) |
| `ip_head=<IP>:6379` | Head **compute IP** from `hostname -I` on the head node (not short hostname) |
| `--` before `python` | **Required** separator (Ray start opts vs entrypoint) |
| `--min-nodes` | Wait until all nodes join |
| `--temp-dir` | Short path on Cyfronet (not in upstream docs; avoids socket errors) |
| `srun --cpu-bind=none` | Required on Cyfronet for every `srun` inside `sbatch` |
| Head then workers | Head starts first (`sleep 30`), then each worker (`sleep 10` between) |

### 2.2 Configure and submit

1. Copy the template if you want a personal variant.
2. Set `#SBATCH --account=<GRANT>-gpu-a100`.
3. Default is **2 nodes**; to scale, change `--nodes` and `--min-nodes` together.

From the repository root:

```bash
sbatch slurm/athena/ray_verify_cluster.sbatch
```

### 2.3 Verify

From `slurm-ray-verify-<jobid>.out`, confirm:

- `Alive nodes: 2` (or your chosen N)
- Cluster resources show expected CPU and GPU counts

**If the job hangs:** check `slurm-*.out` for “Starting Ray head/worker”. Workers must reach the head’s **IP** (`RAY_ADDRESS` in the log). Ensure port 6379 is not blocked between compute nodes.

**Checkpoint:** Submit your modified sbatch and include verification log excerpts.

---

## Part 3 — GPU hyperparameter sweep (Athena)

Submit the full tuning job (same cluster layout, runs [`scripts/run_tune.py`](../scripts/run_tune.py)):

```bash
sbatch slurm/athena/ray_tune_gpu.sbatch
```

Note start/end times in the log. Results go to `$SCRATCH/ray_results/cifar10_tune_lab/`.

Optional flags (edit sbatch or run interactively on a running cluster):

```bash
python scripts/run_tune.py --gpus-per-trial 1 --cpus-per-trial 2 --num-samples 12
```

---

## Part 4 — CPU hyperparameter sweep (Ares)

Log in to **ares.cyfronet.pl**. Use the CPU templates—**no `--gres`**.

Testing partition (short queue):

```bash
sbatch slurm/ares/ray_verify_cluster.sbatch   # plgrid-testing
```

Full CPU sweep:

```bash
sbatch slurm/ares/ray_tune_cpu.sbatch
```

Same `run_tune.py`, with `--gpus-per-trial 0`. Expect **longer** wall time than Athena.

---

## Part 5 — Analysis and deliverables

### Comparison table

Fill in after both jobs complete:

| Metric | Athena (GPU) | Ares (CPU) |
|--------|--------------|------------|
| SLURM nodes | | |
| GPUs allocated (SLURM) | | |
| `num_samples` | | |
| Wall time (minutes) | | |
| Best validation `loss` | | |
| Best validation `accuracy` | | |
| Ray `CPU` / `GPU` in cluster | | |

### Short answers (½–1 page)

1. Why must the CPU baseline run on Ares instead of Athena?
2. What limits how many Tune trials run in parallel on your cluster?
3. What happens if `--num-cpus` passed to `ray start` is **larger** than `SLURM_CPUS_PER_TASK`?

### Deliverables

1. Your modified `ray_verify_cluster.sbatch` (Athena) with grant filled in.
2. `slurm-*.out` excerpts: `ray status` / verify output + tune summary (`Best config`, wall time).
3. Completed comparison table and short answers.

---

## Scaling (optional)

To use **4 nodes** on Athena:

```bash
#SBATCH --nodes=4
```

Ensure `#SBATCH --nodes` matches `--min-nodes`. More GPUs per node: `#SBATCH --gres=gpu:2` and tune `--gpus-per-trial` accordingly.

---

## References

- [Ray on SLURM](https://docs.ray.io/en/latest/cluster/vms/user-guides/community/slurm.html)
- [PyTorch + Ray Tune CIFAR tutorial](https://pytorch.org/tutorials/beginner/hyperparameter_tuning_tutorial.html)
- [Cyfronet batch examples](https://docs.hpc.cyfronet.pl/environment/batch-system/examples/)
