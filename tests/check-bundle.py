"""Check the complete Release archive before supplying it to a Hyper-V host."""
import argparse
import hashlib
import json
from pathlib import Path, PurePosixPath
from zipfile import ZipFile
import sys

sys.path.insert(0,str(Path(__file__).resolve().parents[1]))
from release.bundle import check_elf


def verify(path, arch):
    with ZipFile(path) as z:
        if z.testzip() or len(set(z.namelist()))!=len(z.infolist()):
            raise ValueError("Archive CRC error or duplicate path")
        for name in z.namelist():
            p=PurePosixPath(name)
            if p.is_absolute() or ".." in p.parts or "\\" in name or ":" in name or p.parts[0] in ("drivers","device.json"):
                raise ValueError("Invalid bundle member: "+name)
        meta=json.loads(z.read("manifest.json"))
        if meta["schemaVersion"]!=1 or meta["arch"]!=arch:
            raise ValueError("Manifest architecture/schema mismatch")
        def check(name,sha,types):
            data=z.read(name)
            check_elf(data,arch,types)
            if hashlib.sha256(data).hexdigest()!=sha:
                raise ValueError("Hash mismatch for "+name)
        names={"libdxcore.so","libd3d12.so","libd3d12core.so"}
        pinned=json.loads((Path(__file__).resolve().parents[1]/"host/wsl-runtime.json").read_text())
        expected={r["name"]:r["sha256"] for r in pinned["files"] if r["arch"]==arch}
        if set(meta["libraries"])!=names or meta["libraries"]!=expected:
            raise ValueError("Unrecognized DirectX runtime")
        for name,sha in expected.items():
            check("lib/"+name,sha,(3,))
        check("guest/d3d12-compute",meta["probeSha256"],(2,3))
        entries=json.loads(z.read("prebuilt/index.json"))
        if not entries or entries!=meta["kernels"]:
            raise ValueError("Kernel index mismatch")
        modules=set()
        for e in entries:
            release=e["release"]
            if (release in modules or e["arch"]!=arch or e["name"]!="dxgkrnl" or
                    e["vermagic"].split()[0]!=release):
                raise ValueError("Invalid module entry")
            modules.add(release)
            check(f"prebuilt/{arch}/{release}/dxgkrnl.ko",e["sha256"],(1,))
        allowed_binaries={"lib/"+name for name in expected} | {"guest/d3d12-compute"}
        allowed_binaries.update(f"prebuilt/{arch}/{release}/dxgkrnl.ko" for release in modules)
        for name in z.namelist():
            if name not in allowed_binaries:
                with z.open(name) as member:
                    if member.read(4).startswith((b"\x7fELF", b"MZ")):
                        raise ValueError("Unexpected executable: "+name)
        for n in ("guest/setup","guest/gpupv-guest","guest/sign-module.py","kernel/build","kernel/dkms.conf"):
            z.getinfo(n)
        return sorted(modules)


if __name__=="__main__":
    p=argparse.ArgumentParser()
    p.add_argument("archive",type=Path)
    p.add_argument("arch",choices=("x86_64","aarch64"))
    args=p.parse_args()
    print(args.arch,verify(args.archive,args.arch))
