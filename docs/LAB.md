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

### 0.1 Python virtualenv (Athena **and** Ares)

| Path | Visible on Athena? | Visible on Ares? |
|------|-------------------|------------------|
| `$HOME/ray-slurm` (git clone) | yes | yes |
| `$HOME/venv-ray` | yes | yes |
| `$SCRATCH/...` | Athena only | Ares only |

Use **`$HOME/venv-ray`** for Ray on both systems. Setup differs:

| System | PyTorch | Ray / Tune |
|--------|---------|------------|
| **Athena** | `module load PyTorch-Geometric/2.5.1` + pip in venv | `bash scripts/setup_env.sh` |
| **Ares** | `module load pytorch/...` + `torchvision/...` | `bash scripts/setup_env_ares.sh` |

**Athena** (interactive GPU compute job):

```bash
cd $HOME/ray-slurm
bash scripts/setup_env.sh
source $HOME/venv-ray/bin/activate
python -c "import torch, ray; print('ok')"
```

**Ares** (interactive CPU compute job)—PyTorch from modules (`module avail torch`):

```bash
cd $HOME/ray-slurm
bash scripts/setup_env_ares.sh    # venv --system-site-packages; pip installs ray, pydantic only
source $HOME/venv-ray/bin/activate
module load pytorch/1.10.0-foss-2021a-cuda-11.3.1
module load torchvision/0.11.1-foss-2021a-cuda-11.3.1-pytorch-1.10.0
python -c "import torch, torchvision, ray; print('ok')"
```

If you already created `$HOME/venv-ray` with `setup_env.sh` only (pip torch, no `--system-site-packages`), recreate on Ares with `setup_env_ares.sh` before CPU jobs.

If you only have `$SCRATCH/venv-ray` on Athena, use `export VENV_PATH=$SCRATCH/venv-ray` for Athena sbatch (GPU path still uses PyG module there).

**Athena-only shortcut:** if you keep the venv in scratch, set before each Athena `sbatch`:

```bash
export VENV_PATH=$SCRATCH/venv-ray
```

Ares scripts always use `$HOME/venv-ray` unless you set `VENV_PATH` the same way.

### 0.2 Ray version and temp directory

```bash
source $HOME/venv-ray/bin/activate
ray --version    # Ray 2.x
```

Ray’s default session path under deep `$SCRATCH` trees can exceed the Unix socket path limit (~107 bytes). Always use a **short** temp directory:

```bash
export RAY_TMPDIR="/tmp/ray-${USER}"
mkdir -p "$RAY_TMPDIR"
```

SLURM templates pass `--temp-dir="$RAY_TMPDIR"` to Ray.

### 0.3 Download CIFAR-10

`$SCRATCH` is **per supercomputer**. Download on **both** Athena and Ares (inside a compute job on each):

```bash
source $HOME/venv-ray/bin/activate
export DATA_DIR="${SCRATCH}/data/cifar10"
bash scripts/download_cifar.sh
```

Tune results also go to `$SCRATCH/ray_results` on the machine where the job runs.

---

## Part 0b — Quick check on Ares (optional)

On **ares.cyfronet.pl**, request a short CPU node and confirm Ray imports:

```bash
srun -p plgrid-testing -N 1 -n 1 --cpus-per-task=4 --mem=8G \
  -A <GRANT>-cpu --time=00:30:00 --pty /bin/bash -l

cd $HOME/ray-slurm
module load pytorch/1.10.0-foss-2021a-cuda-11.3.1
module load torchvision/0.11.1-foss-2021a-cuda-11.3.1-pytorch-1.10.0
source $HOME/venv-ray/bin/activate
export RAY_TMPDIR="/tmp/ray-${USER}"
mkdir -p "$RAY_TMPDIR"
ray --version
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
source $HOME/venv-ray/bin/activate
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

Athena is **GPU-only** for policy reasons; the CPU baseline runs on **Ares** with the same [`scripts/run_tune.py`](../scripts/run_tune.py) (`--gpus-per-trial 0`).

### 4.1 What you need on Ares

1. Repo at `$HOME/ray-slurm` (same clone as Athena).
2. Venv from **`bash scripts/setup_env_ares.sh`** (`$HOME/venv-ray`, `--system-site-packages`).
3. Each job loads modules (already in sbatch):

   ```bash
   module load pytorch/1.10.0-foss-2021a-cuda-11.3.1
   module load torchvision/0.11.1-foss-2021a-cuda-11.3.1-pytorch-1.10.0
   ```

   CUDA in the module name is normal; trials still run on **CPU** (`--gpus-per-trial 0`). Other versions: `module avail torch`.

4. CIFAR-10 under **`$SCRATCH/data/cifar10` on Ares** (Part 0.3 on a compute node).
5. `#SBATCH --account=<GRANT>-cpu` in [`slurm/ares/*.sbatch`](../slurm/ares/).

### 4.2 Configure and verify (2 nodes)

SSH to Ares, edit grant in [`slurm/ares/ray_verify_cluster.sbatch`](../slurm/ares/ray_verify_cluster.sbatch), then:

```bash
cd $HOME/ray-slurm
sbatch slurm/ares/ray_verify_cluster.sbatch
```

Check `slurm-ray-verify-cpu-<jobid>.out` for `Alive nodes: 2` (same pattern as Athena: head IP, staggered `ray start`, verify on batch node).

### 4.3 Full CPU tune job

```bash
sbatch slurm/ares/ray_tune_cpu.sbatch
```

Follow logs: `tail -f slurm-ray-tune-cpu-<jobid>.out`

Wall time is usually **much longer** than Athena; use the same `num_samples` in [`config/lab_defaults.yaml`](../config/lab_defaults.yaml) for a fair comparison.

### 4.4 Troubleshooting on Ares

| Problem | Fix |
|---------|-----|
| `venv-ray: No such file` | Run Part 0.1 on Ares (or copy venv to `$HOME`) |
| `No module named torch` | Run `setup_env_ares.sh`; load pytorch+torchvision modules before `source` venv |
| `pydantic` ImportError | `pip install pydantic` |
| CIFAR download fails | Run `download_cifar.sh` inside a **compute** job, not login |
| Hang after workers | Pull latest sbatch (run verify on batch node, not second `srun`) |

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
