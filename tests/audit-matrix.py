#!/usr/bin/env python3
"""Check module identity, return status and source digest in container logs."""
import hashlib
import json
from pathlib import Path
import re
import sys


def source_digest(root):
    result = hashlib.sha256()
    paths = sorted((root/"kernel").rglob("*"),key=lambda p:p.as_posix())
    for path in paths:
        if path.is_file():
            result.update(path.relative_to(root).as_posix().encode()+b"\0")
            result.update(hashlib.sha256(path.read_bytes()).digest())
    return result.hexdigest()


def audit(root,reports):
    expected = source_digest(root)
    rows = []
    for meta in sorted(reports.glob("*.json")):
        result = json.loads(meta.read_text(encoding="utf-8"))
        log = meta.with_suffix(".log").read_text(encoding="utf-8",errors="replace")
        if result["sources_sha256"] != expected or f"sources_sha256={expected}" not in log.splitlines()[0]:
            raise ValueError(f"{meta.stem}: source digest mismatch")
        code = int(log.splitlines()[-1].removeprefix("exit="))
        if (code != result["exit"] or (code==0) != result["passed"]):
            raise ValueError(f"{meta.stem}: inconsistent exit status")
        match = re.search(r"^vermagic:\s+(\S+)",log,re.M)
        binary = re.search(r"^([a-f0-9]{64})\s+\S*/dxgkrnl\.ko$",log,re.M)
        if code == 0 and not (match and binary and re.search(r"^name:\s+dxgkrnl$",log,re.M)
                              and re.search(r"^HEADER_TREE=/",log,re.M)):
            raise ValueError(f"{meta.stem}: missing kernel or module evidence")
        rows.append(dict(target=meta.stem,image=result["image"],passed=code==0,
                         kernel=match[1] if match else None,sha256=binary[1] if binary else None,
                         log=str(meta.with_suffix(".log").relative_to(root).as_posix())))
    if not rows:
        raise ValueError("No completed cases in report directory")
    return rows


if __name__=="__main__":
    root = Path(__file__).resolve().parents[1]
    folder = Path(sys.argv[1]).resolve() if len(sys.argv)>1 else root/"artifacts/reports/compile-matrix/final"
    print(json.dumps(audit(root,folder),indent=2))

