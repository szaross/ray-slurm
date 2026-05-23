# Instructor notes — Ray + SLURM lab

## Overview

Students configure **multi-node Ray on Athena** via SLURM (`ray symmetric-run`), then run the shared [`scripts/run_tune.py`](../scripts/run_tune.py) twice:

| Run | System | SLURM template | Tune GPUs |
|-----|--------|----------------|-----------|
| A | Athena | `slurm/athena/ray_tune_gpu.sbatch` | `--gpus-per-trial 1` |
| B | Ares | `slurm/ares/ray_tune_cpu.sbatch` | `--gpus-per-trial 0` |

Default lab settings: [`config/lab_defaults.yaml`](../config/lab_defaults.yaml) — 12 trials, 3 epochs, small search space.

## Expected runtime (after validation)

Adjust `lab_defaults.yaml` if your pilot runs exceed the course slot.

| Job | Default resources | Rough expectation |
|-----|-------------------|-------------------|
| Athena verify | 2 nodes × 1 GPU × 16 CPU | 5–15 min |
| Athena tune | same | 45–120 min |
| Ares tune | 2 nodes × 24 CPU | 2–6 h (CPU much slower) |

CPU runs are intentionally slower; students compare **relative** speedup, not equal wall times.

## Grading rubric (100%)

| Criterion | Weight | Pass indicators |
|-----------|--------|-----------------|
| Multi-node Ray on Athena | 50% | Correct `#SBATCH` nodes/tasks/GRES; `verify_cluster.py` shows N alive nodes; sensible `ip_head` |
| Jobs executed + artifacts | 30% | Both sbatch logs; Tune best metric printed; results under `$SCRATCH/ray_results` |
| Analysis | 20% | Completed table; explains Athena GPU policy and Tune parallelism |

## Common failures

| Symptom | Likely cause | Fix |
|---------|--------------|-----|
| `AF_UNIX path too long` | Ray temp under deep `$SCRATCH` | `export RAY_TMPDIR=/tmp/ray-$USER`, `--temp-dir` |
| Workers never join | Wrong `ip_head` / firewall | Use head node hostname from `scontrol`; try IP from compute node |
| Ray GPU = 0 on Athena | Missing `#SBATCH --gres=gpu:1` | Add GRES; check `SLURM_GPUS_PER_TASK` |
| Tune hangs / OOM | `cpus-per-trial` too high | Lower in sbatch CLI (2 GPU, 4 CPU) |
| CIFAR download fails on login | Network/policy | Run `download_cifar.sh` inside compute job |
| `symmetric-run` not found | Ray < 2.49 | Re-run `setup_env.sh` |
| Ares: no torch | Module only on Athena | `pip install torch torchvision` in shared venv on Ares job |

## HPC validation checklist (maintainer)

Run before each semester:

1. [ ] Athena: single-node `ray start` + `verify_cluster.py`
2. [ ] Athena: `sbatch slurm/athena/ray_verify_cluster.sbatch` — 2 nodes alive
3. [ ] Athena: `sbatch slurm/athena/ray_tune_gpu.sbatch` — completes, best metric logged
4. [ ] Ares: `sbatch slurm/ares/ray_tune_cpu.sbatch` — completes with `gpu=0`
5. [ ] Tune `num_samples` / `max_epochs` fit time budget; update `lab_defaults.yaml` if needed

Local sanity check (no cluster):

```bash
bash scripts/validate_local.sh
```

## Environment notes

- **Athena:** `module load PyTorch-Geometric/2.5.1` + venv at `$SCRATCH/venv-ray` (tested by maintainer).
- **Ares:** No GPU in sbatch; use `plgrid` or `plgrid-testing` for verify.
- **Accounts:** ` <grant>-gpu-a100` (Athena), `<grant>-cpu` (Ares).
- **Storage:** CIFAR and Tune results on `$SCRATCH`; 7-day job dir cleanup on scratch—students should copy artifacts to `$HOME` for submission.

## Customization

- Shorter lab: set `num_samples: 6`, `max_epochs: 2` in `lab_defaults.yaml`.
- Single-node fallback on Ares: `#SBATCH --nodes=1`, `--min-nodes 1` (document as optional in LAB.md).
- Heavier model: switch to Ray MNIST example (not in repo by default).

## References

- Plan/spec: [task.md](../task.md)
- Maintainer spike: [README.md](../README.md)
