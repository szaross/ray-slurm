# ray-slurm

Lab materials for **Ray** and **Ray Tune** on Cyfronet **Athena** (SLURM): multi-node cluster setup + **GPU vs CPU** hyperparameter sweeps on the same system.

**Student instructions:** [docs/LAB.md](docs/LAB.md)

**Instructor notes:** [docs/INSTRUCTOR.md](docs/INSTRUCTOR.md)

## Repository layout

```
config/lab_defaults.yaml
scripts/run_tune.py          # CIFAR-10 Ray Tune workload
scripts/verify_cluster.py
scripts/setup_env.sh
slurm/athena/                # verify, ray_tune_gpu, ray_tune_cpu
docs/LAB.md
```

## Quickstart (Athena)

Create the venv once on a **compute node** (`bash scripts/setup_env.sh` → `$SCRATCH/venv-ray`).

Submit all `sbatch` jobs from the **login node** (not from inside `srun`):

```bash
cd $HOME/ray-slurm
sbatch slurm/athena/ray_verify_cluster.sbatch
sbatch slurm/athena/ray_tune_gpu.sbatch
sbatch slurm/athena/ray_tune_cpu.sbatch
```

## Links

- [Athena documentation](https://docs.hpc.cyfronet.pl/supercomputers/athena/)
- [Ray SLURM guide](https://docs.ray.io/en/latest/cluster/vms/user-guides/community/slurm.html)
