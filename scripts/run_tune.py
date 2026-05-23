#!/usr/bin/env python3
"""
CIFAR-10 hyperparameter sweep with Ray Tune (lab workload).

Adapted from: https://pytorch.org/tutorials/beginner/hyperparameter_tuning_tutorial.html
Students run this script as-is; they configure SLURM and Ray, not the tuning logic.
"""

from __future__ import annotations

import argparse
import os
import sys

os.environ.setdefault("RAY_ACCEL_ENV_VAR_OVERRIDE_ON_ZERO", "0")
import tempfile
import time
from functools import partial
from pathlib import Path

import ray
import torch
import torch.nn as nn
import torch.nn.functional as F
import torch.optim as optim
import torchvision
import torchvision.transforms as transforms
import yaml
from ray import tune
from ray.tune import Checkpoint
from ray.tune.schedulers import ASHAScheduler
from torch.utils.data import DataLoader, random_split

REPO_ROOT = Path(__file__).resolve().parents[1]
DEFAULT_CONFIG = REPO_ROOT / "config" / "lab_defaults.yaml"


def load_lab_config(path: Path) -> dict:
    with path.open() as f:
        return yaml.safe_load(f)


def resolve_path(value: str | None, env_var: str, default_suffix: str) -> Path:
    if value:
        return Path(os.path.expandvars(value))
    base = os.environ.get(env_var)
    if base:
        return Path(base) / default_suffix
    return Path.home() / default_suffix


class Net(nn.Module):
    def __init__(self, l1: int = 120, l2: int = 84) -> None:
        super().__init__()
        self.conv1 = nn.Conv2d(3, 6, 5)
        self.pool = nn.MaxPool2d(2, 2)
        self.conv2 = nn.Conv2d(6, 16, 5)
        self.fc1 = nn.Linear(16 * 5 * 5, l1)
        self.fc2 = nn.Linear(l1, l2)
        self.fc3 = nn.Linear(l2, 10)

    def forward(self, x: torch.Tensor) -> torch.Tensor:
        x = self.pool(F.relu(self.conv1(x)))
        x = self.pool(F.relu(self.conv2(x)))
        x = torch.flatten(x, 1)
        x = F.relu(self.fc1(x))
        x = F.relu(self.fc2(x))
        return self.fc3(x)


def load_data(data_dir: str):
    transform = transforms.Compose(
        [
            transforms.ToTensor(),
            transforms.Normalize(
                (0.4914, 0.48216, 0.44653),
                (0.2022, 0.19932, 0.20086),
            ),
        ]
    )
    trainset = torchvision.datasets.CIFAR10(
        root=data_dir, train=True, download=True, transform=transform
    )
    testset = torchvision.datasets.CIFAR10(
        root=data_dir, train=False, download=True, transform=transform
    )
    return trainset, testset


def train_cifar(config: dict, data_dir: str | None = None) -> None:
    data_dir = data_dir or "./data"
    net = Net(config["l1"], config["l2"])
    device = "cuda" if torch.cuda.is_available() else "cpu"
    net = net.to(device)
    if device == "cuda" and torch.cuda.device_count() > 1:
        net = nn.DataParallel(net)

    criterion = nn.CrossEntropyLoss()
    optimizer = optim.SGD(net.parameters(), lr=config["lr"], momentum=0.9)

    checkpoint = tune.get_checkpoint()
    if checkpoint:
        with checkpoint.as_directory() as checkpoint_dir:
            checkpoint_path = Path(checkpoint_dir) / "checkpoint.pt"
            state = torch.load(checkpoint_path, weights_only=False)
            start_epoch = state["epoch"] + 1
            net.load_state_dict(state["net_state_dict"])
            optimizer.load_state_dict(state["optimizer_state_dict"])
    else:
        start_epoch = 0

    trainset, _ = load_data(data_dir)
    val_size = int(len(trainset) * 0.2)
    train_size = len(trainset) - val_size
    train_subset, val_subset = random_split(trainset, [train_size, val_size])

    num_workers = int(config.get("num_workers", 4))
    batch_size = int(config["batch_size"])
    trainloader = DataLoader(
        train_subset,
        batch_size=batch_size,
        shuffle=True,
        num_workers=num_workers,
    )
    valloader = DataLoader(
        val_subset,
        batch_size=batch_size,
        shuffle=False,
        num_workers=num_workers,
    )

    max_epochs = int(config["max_epochs"])
    for epoch in range(start_epoch, max_epochs):
        net.train()
        for inputs, labels in trainloader:
            inputs, labels = inputs.to(device), labels.to(device)
            optimizer.zero_grad()
            loss = criterion(net(inputs), labels)
            loss.backward()
            optimizer.step()

        net.eval()
        val_loss = 0.0
        val_steps = 0
        correct = 0
        total = 0
        with torch.no_grad():
            for inputs, labels in valloader:
                inputs, labels = inputs.to(device), labels.to(device)
                outputs = net(inputs)
                _, predicted = torch.max(outputs.data, 1)
                total += labels.size(0)
                correct += (predicted == labels).sum().item()
                val_loss += criterion(outputs, labels).item()
                val_steps += 1

        checkpoint_data = {
            "epoch": epoch,
            "net_state_dict": net.state_dict(),
            "optimizer_state_dict": optimizer.state_dict(),
        }
        with tempfile.TemporaryDirectory() as checkpoint_dir:
            checkpoint_path = Path(checkpoint_dir) / "checkpoint.pt"
            torch.save(checkpoint_data, checkpoint_path)
            ckpt = Checkpoint.from_directory(checkpoint_dir)
            tune.report(
                {"loss": val_loss / max(val_steps, 1), "accuracy": correct / max(total, 1)},
                checkpoint=ckpt,
            )


def build_search_space(cfg: dict) -> dict:
    sp = cfg["search_space"]
    return {
        "l1": tune.choice(sp["l1"]),
        "l2": tune.choice(sp["l2"]),
        "lr": tune.loguniform(sp["lr_min"], sp["lr_max"]),
        "batch_size": tune.choice(sp["batch_size"]),
        "max_epochs": cfg["max_epochs"],
        "num_workers": cfg.get("num_workers", 4),
    }


def parse_args() -> argparse.Namespace:
    p = argparse.ArgumentParser(description="Run CIFAR-10 Ray Tune lab sweep.")
    p.add_argument(
        "--lab-config",
        type=Path,
        default=DEFAULT_CONFIG,
        help="YAML file with lab defaults",
    )
    p.add_argument("--data-dir", type=str, default=None)
    p.add_argument("--num-samples", type=int, default=None)
    p.add_argument("--cpus-per-trial", type=float, default=None)
    p.add_argument("--gpus-per-trial", type=float, default=None)
    p.add_argument("--experiment-name", type=str, default=None)
    p.add_argument("--storage-path", type=str, default=None)
    p.add_argument(
        "--verify-only",
        action="store_true",
        help="Only verify Ray cluster (for SLURM verify job)",
    )
    return p.parse_args()


def main() -> int:
    args = parse_args()
    lab = load_lab_config(args.lab_config)

    if args.verify_only:
        import subprocess

        verify_script = Path(__file__).resolve().parent / "verify_cluster.py"
        return subprocess.call([sys.executable, str(verify_script)])

    data_dir = str(
        resolve_path(
            args.data_dir or lab.get("data_dir"),
            "SCRATCH",
            "data/cifar10",
        )
    )
    os.makedirs(data_dir, exist_ok=True)

    num_samples = args.num_samples or lab["num_samples"]
    cpus_per_trial = args.cpus_per_trial if args.cpus_per_trial is not None else lab["cpus_per_trial"]
    gpus_per_trial = args.gpus_per_trial
    if gpus_per_trial is None:
        gpus_per_trial = lab.get("gpus_per_trial")
    if gpus_per_trial is None:
        gpus_per_trial = 1.0 if torch.cuda.is_available() else 0.0

    storage_path = str(
        resolve_path(
            args.storage_path or lab.get("storage_path"),
            "SCRATCH",
            "ray_results",
        )
    )
    experiment_name = args.experiment_name or lab["experiment_name"]

    connected_here = False
    if not ray.is_initialized():
        ray.init(address="auto")
        connected_here = True

    scheduler = ASHAScheduler(
        max_t=lab["max_epochs"],
        grace_period=lab.get("grace_period", 1),
        reduction_factor=2,
    )

    param_space = build_search_space(lab)
    trainable = tune.with_resources(
        partial(train_cifar, data_dir=data_dir),
        resources={"cpu": cpus_per_trial, "gpu": gpus_per_trial},
    )

    print(f"Data dir: {data_dir}")
    print(f"Storage: {storage_path}")
    print(f"Trials: {num_samples}, cpus/trial={cpus_per_trial}, gpus/trial={gpus_per_trial}")
    print(f"CUDA available: {torch.cuda.is_available()}")

    started = time.time()
    tuner = tune.Tuner(
        trainable,
        param_space=param_space,
        tune_config=tune.TuneConfig(
            metric="loss",
            mode="min",
            scheduler=scheduler,
            num_samples=num_samples,
        ),
        run_config=tune.RunConfig(
            name=experiment_name,
            storage_path=storage_path,
        ),
    )
    results = tuner.fit()
    elapsed = time.time() - started

    best = results.get_best_result(metric="loss", mode="min")
    print("\n=== Sweep finished ===")
    print(f"Wall time (s): {elapsed:.1f}")
    print(f"Best config: {best.config}")
    print(f"Best metrics: {best.metrics}")
    print(f"Results directory: {storage_path}/{experiment_name}")
    if connected_here:
        ray.shutdown()
    return 0


if __name__ == "__main__":
    sys.exit(main())
