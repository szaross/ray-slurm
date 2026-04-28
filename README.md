# ray-slurm


## starting ray on a Athenna node
```bash
module load PyTorch-Geometric/2.5.1
source $SCRATCH/venv-ray/bin/activate  
ray start --head --num-gpus=1 --temp-dir=/tmp/ray-$USER
```

We need to investigate where to put ray tmp files - default path is too long for Unix systems (above 107 bytes).