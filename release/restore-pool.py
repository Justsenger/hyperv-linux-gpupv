"""Restore the audited modules from the producer jobs of this repository."""
import argparse
import hashlib
import json
import os
import shutil
import subprocess
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def restore(arch, output):
    lock = json.loads((ROOT / "targets/prebuilt-pool.json").read_text())
    tree = subprocess.check_output(["git", "rev-parse", "HEAD:kernel"], text=True).strip()
    if tree != lock["kernelTree"]:
        raise ValueError("Kernel sources changed. Refresh the audited module pool.")
    releases = set()
    for group in lock["architectures"][arch]:
        name = "modules-" + arch + "-" + group["target"]
        with tempfile.TemporaryDirectory() as directory:
            subprocess.run(["gh", "run", "download", str(group["run"]), "--repo",
                            os.environ["GITHUB_REPOSITORY"], "--name", name,
                            "--dir", directory], check=True)
            for release, expected in group["modules"].items():
                if release in releases:
                    raise ValueError("Duplicate locked module: " + release)
                source = Path(directory) / group["target"] / release
                entry = json.loads((source / "module.json").read_text())
                module = source / "dxgkrnl.ko"
                if ((entry["arch"], entry["target"], entry["release"], entry["sha256"])
                        != (arch, group["target"], release, expected)
                        or hashlib.sha256(module.read_bytes()).hexdigest() != expected):
                    raise ValueError("Producer artifact mismatch: " + str(source))
                dest = output / release
                dest.mkdir(parents=True, exist_ok=False)
                shutil.copyfile(module, dest / module.name)
                shutil.copyfile(source / "module.json", dest / "module.json")
                releases.add(release)
    print(f"Restored {len(releases)} distinct {arch} kernel releases", flush=True)


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("arch", choices=["aarch64", "x86_64"])
    parser.add_argument("output", type=Path)
    args = parser.parse_args()
    restore(args.arch, args.output)
