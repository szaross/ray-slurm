# ray-slurm

Lab materials for running **Ray** and **Ray Tune** on Cyfronet **Athena** (multi-node GPU, SLURM) and comparing with a **CPU** baseline on **Ares**.

**Student instructions:** [docs/LAB.md](docs/LAB.md)

**Instructor notes:** [docs/INSTRUCTOR.md](docs/INSTRUCTOR.md)

## Repository layout

```
config/lab_defaults.yaml    # trials, epochs, search space
scripts/run_tune.py         # CIFAR-10 Ray Tune workload (students do not edit)
scripts/verify_cluster.py   # cluster sanity check
scripts/setup_env.sh        # venv + pip install
slurm/athena/               # GPU job templates
slurm/ares/                 # CPU job templates
docs/LAB.md                 # lab handout
```

## Maintainer quickstart (Athena)

Verified single-node startup:

```bash
module load PyTorch-Geometric/2.5.1
source $SCRATCH/venv-ray/bin/activate
export RAY_TMPDIR="/tmp/ray-$USER"
mkdir -p "$RAY_TMPDIR"
ray start --head --num-gpus=1 --temp-dir="$RAY_TMPDIR"
```

Ray’s default temp path under long `$SCRATCH` paths can exceed the Unix domain socket path limit (~107 bytes). Use `/tmp/ray-$USER` or another short path.

## Setup

```bash
# On a compute node (interactive SLURM job):
bash scripts/setup_env.sh
bash scripts/download_cifar.sh
```

Multi-node jobs use staggered `ray start --head` / `ray start --address=...` per node (Athena `symmetric-run` was unreliable). See `slurm/athena/*.sbatch`.

## Submit jobs

From repo root, after replacing `<GRANT>` in the sbatch files:

```bash
sbatch slurm/athena/ray_verify_cluster.sbatch
sbatch slurm/athena/ray_tune_gpu.sbatch
# On Ares:
sbatch slurm/ares/ray_tune_cpu.sbatch
```

## Local validation

Syntax and template checks only (no Ray install on your laptop):

```bash
bash scripts/validate_local.sh
```

Install Ray inside your Cyfronet venv (`scripts/setup_env.sh` on a compute node). Full cluster validation: [docs/INSTRUCTOR.md](docs/INSTRUCTOR.md).

## Open questions / spikes

- If multi-node workers fail to connect using hostname for `ip_head`, resolve the head node IP on the compute network (`hostname -i` or IB address) and substitute in the sbatch script.
- Pin exact Ray/PyTorch versions in `requirements.txt` after semester pilot runs.

## Links

- [Athena documentation](https://docs.hpc.cyfronet.pl/supercomputers/athena/)
- [Ares documentation](https://docs.hpc.cyfronet.pl/supercomputers/ares/)
- [Ray SLURM guide](https://docs.ray.io/en/latest/cluster/vms/user-guides/community/slurm.html)
