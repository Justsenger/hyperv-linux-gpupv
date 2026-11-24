"""Build the redistributable toolchain, excluding host-specific binary drivers."""
from pathlib import Path
from zipfile import ZipFile, ZipInfo, ZIP_DEFLATED
import argparse
import hashlib
import os
import tempfile
import sys

if sys.argv[1:2] == ["bundle"]:
    from release.bundle import main
    del sys.argv[1]
    main()
    sys.exit(0)

root = Path(__file__).resolve().parent
inputs = [".gitignore", ".gitattributes", "README.md", "LICENSE", "COMPATIBILITY.md", "PROGRESS.md", "build.py", "host",
          "guest", "kernel", "release", "targets", ".github", "tests", "docs", "artifacts/reports", "artifacts/state.json"]
files = []
for name in inputs:
    p = root / name
    files.extend(sorted(p.rglob("*")) if p.is_dir() else [p])
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("--output-dir", type=Path, default=root / "dist")
out = parser.parse_args().output_dir
out.mkdir(exist_ok=True, parents=True)
dest = out / "hyperv-linux-gpupv-source.zip"
with tempfile.NamedTemporaryFile(dir=out, delete=False) as tmp:
    tmp_path = Path(tmp.name)
try:
    with ZipFile(tmp_path, "w") as archive:
        for path in sorted(files,key=lambda p:p.relative_to(root).as_posix()):
            if not path.is_file() or "__pycache__" in path.parts:
                continue
            if path.name.lower().partition(".so")[0] in {"libd3d12", "libd3d12core", "libdxcore"} and ".so" in path.name.lower():
                raise ValueError(f"Proprietary library in source inputs: {path}")
            rel = path.relative_to(root).as_posix()
            info = ZipInfo(rel)
            info.create_system = 3
            data = path.read_bytes()
            if data.startswith((b"\x7fELF", b"MZ")):
                raise ValueError(f"Unexpected executable or library in public source: {rel}")
            executable = data.startswith(b"#!") and rel.startswith(("guest/", "kernel/", "tests/"))
            info.external_attr = (0o100755 if executable else 0o100644) << 16
            archive.writestr(info, data, compress_type=ZIP_DEFLATED, compresslevel=9)
    os.replace(tmp_path, dest)
finally:
    tmp_path.unlink(missing_ok=True)
print(hashlib.sha256(dest.read_bytes()).hexdigest(), dest.name)


