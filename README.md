# ray-slurm

Lab materials for **Ray** and **Ray Tune** on Cyfronet **Athena** (SLURM): multi-node cluster setup and **GPU vs CPU** hyperparameter sweeps.

- **Students:** [docs/LAB.md](docs/LAB.md)
- **Instructors:** [docs/INSTRUCTOR.md](docs/INSTRUCTOR.md)

## Layout

```
config/lab_defaults.yaml
scripts/run_tune.py
scripts/verify_cluster.py
scripts/setup_env.sh
slurm/athena/ray_cluster.sh      # shared cluster logic (sourced by sbatch)
slurm/athena/ray_verify_cluster.sbatch
slurm/athena/ray_tune_gpu.sbatch
slurm/athena/ray_tune_cpu.sbatch
docs/LAB.md
```

## Quickstart

1. On a **compute node**: `bash scripts/setup_env.sh` → venv at `$SCRATCH/venv-ray`
2. On the **login node**:

```bash
cd $HOME/ray-slurm
sbatch slurm/athena/ray_verify_cluster.sbatch
sbatch slurm/athena/ray_tune_gpu.sbatch
sbatch slurm/athena/ray_tune_cpu.sbatch
```

## Links

- [Athena documentation](https://docs.hpc.cyfronet.pl/supercomputers/athena/)
- [Ray SLURM guide](https://docs.ray.io/en/latest/cluster/vms/user-guides/community/slurm.html)
