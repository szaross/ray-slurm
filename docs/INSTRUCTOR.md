# Instructor notes — Ray + SLURM lab

## Overview

Students configure **multi-node Ray on Athena** via SLURM (classic `ray start` in [`slurm/athena/ray_verify_cluster.sbatch`](../slurm/athena/ray_verify_cluster.sbatch)), then run [`scripts/run_tune.py`](../scripts/run_tune.py) twice on the **same** system:

| Run | SLURM template | Tune resources | Results dir |
|-----|----------------|----------------|-------------|
| GPU | `slurm/athena/ray_tune_gpu.sbatch` | `--gpus-per-trial 1` | `cifar10_tune_lab_gpu` |
| CPU | `slurm/athena/ray_tune_cpu.sbatch` | `--gpus-per-trial 0` | `cifar10_tune_lab_cpu` |

Both jobs still use `#SBATCH --gres=gpu:1` (Athena policy). CPUs are not billed for unused GPUs in the same way as “idle” GRES—students should understand **policy vs workload**.

Default lab settings: [`config/lab_defaults.yaml`](../config/lab_defaults.yaml) — 12 trials, 3 epochs.

## Expected runtime

| Job | Default resources | Rough expectation |
|-----|-------------------|-------------------|
| Verify | 2 nodes × 1 GPU × 16 CPU | 5–15 min |
| GPU tune | same | 45–120 min |
| CPU tune | same, 4 h wall limit | 2–6 h |

CPU runs are slower; comparison is **relative** speedup on the same cluster topology.

## Grading rubric (100%)

| Criterion | Weight | Pass indicators |
|-----------|--------|-----------------|
| Multi-node Ray on Athena | 50% | Correct `#SBATCH`; verify shows N alive nodes; head IP in logs |
| Jobs executed + artifacts | 30% | GPU + CPU sbatch logs; results under `$SCRATCH/ray_results` |
| Analysis | 20% | Table + explains GRES on CPU job and Tune parallelism |

## Common failures

| Symptom | Likely cause | Fix |
|---------|--------------|-----|
| `sbatch` fails or wrong paths from compute node | Submitted inside `srun` / compute shell | Run `sbatch` only from the **login node**; `cd` to repo first |
| `AF_UNIX path too long` | Ray temp under deep `$SCRATCH` | `RAY_TMPDIR=/tmp/ray-$USER`, `--temp-dir` |
| Workers never join | Wrong address | Head **compute IP** (`172.23.x.x:6379`) |
| `SLURM_GPUS_PER_TASK: unbound variable` | `set -u` | `${SLURM_GPUS_PER_TASK:-${SLURM_GPUS_ON_NODE:-1}}` |
| CPU bind errors | Nested `srun` | `--cpu-bind=none` |
| Hang at verify | Second `srun` on head | Run Python on batch node / `--overlap` |
| `pydantic` missing | venv | `pip install pydantic` |
| Tune OOM / slow CPU job | Too many parallel CPU trials | Lower `--cpus-per-trial` or `num_samples` |

## HPC validation checklist

1. [ ] Single-node `ray start` + `verify_cluster.py`
2. [ ] `sbatch slurm/athena/ray_verify_cluster.sbatch` — 2 nodes alive
3. [ ] `sbatch slurm/athena/ray_tune_gpu.sbatch` — completes
4. [ ] `sbatch slurm/athena/ray_tune_cpu.sbatch` — completes with CPU trials
5. [ ] Tune budget fits course slot; adjust `lab_defaults.yaml` if needed

```bash
bash scripts/validate_local.sh
```

## Environment

- `module load PyTorch-Geometric/2.5.1` + venv at `$SCRATCH/venv-ray` (`bash scripts/setup_env.sh` on a compute node)
- CIFAR + Tune results on `$SCRATCH`; copy artifacts to `$HOME` before scratch cleanup

## Customization

- Shorter lab: `num_samples: 6`, `max_epochs: 2`
- More CPU parallelism: lower `cpus-per-trial` in `ray_tune_cpu.sbatch` (watch memory)

## References

- [task.md](../task.md)
- [docs/LAB.md](LAB.md)
