#!/bin/bash
# Offline checks from repo root: syntax + config + templates only.
# Does NOT install Ray, import Ray, or contact SLURM. Use Athena/Ares for real runs.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

echo "=== Python syntax ==="
python3 -m py_compile scripts/verify_cluster.py scripts/run_tune.py

echo "=== YAML config ==="
python3 -c "import yaml; yaml.safe_load(open('config/lab_defaults.yaml'))"

echo "=== SBATCH templates present ==="
for f in slurm/athena/ray_verify_cluster.sbatch slurm/athena/ray_tune_gpu.sbatch \
         slurm/ares/ray_verify_cluster.sbatch slurm/ares/ray_tune_cpu.sbatch; do
  test -f "$f" || { echo "Missing $f"; exit 1; }
  grep -q '<GRANT>' "$f" && grep -q 'ray.scripts.symmetric_run' "$f" && echo "OK: $f"
done

echo "All local checks passed."
