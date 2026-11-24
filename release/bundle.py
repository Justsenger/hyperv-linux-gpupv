"""Assemble an architecture-specific compute bundle from audited CI output."""
import argparse
import hashlib
import json
import re
import tempfile
import urllib.request
from pathlib import Path
from zipfile import ZIP_DEFLATED, ZipFile

ROOT = Path(__file__).resolve().parents[1]
MACHINES = {"x86_64": 62, "aarch64": 183}


def digest(data):
    return hashlib.sha256(data).hexdigest()


def check_elf(data, arch, types):
    if (data[:6] != b"\x7fELF\x02\x01" or len(data)<64 or
            int.from_bytes(data[16:18],"little") not in types or
            int.from_bytes(data[18:20],"little") != MACHINES[arch]):
        raise ValueError("Unexpected ELF for " + arch)


def build(arch, version, pool, probe, output, cache=None):
    if not re.fullmatch(r"[A-Za-z0-9][A-Za-z0-9._-]*", version):
        raise ValueError("Invalid version")
    inventory=json.loads((ROOT/"host/wsl-runtime.json").read_text())
    meta={"schemaVersion":1,"arch":arch,"version":version,"libraries":{},"kernels":[]}
    name=f"linuxpv-bundle-{arch}-{version}.zip"
    output.mkdir(exist_ok=True,parents=True)
    with tempfile.TemporaryDirectory(dir=output) as temp:
        stage=Path(temp)/name
        with ZipFile(stage,"w",ZIP_DEFLATED) as z:
            for folder in ("kernel","guest"):
                for path in sorted((ROOT/folder).rglob("*")):
                    if path.is_file() and "__pycache__" not in path.parts:
                        with path.open("rb") as source:
                            magic = source.read(4)
                        if magic.startswith((b"\x7fELF", b"MZ")) or path.name == "d3d12-compute":
                            raise ValueError("Unexpected binary in source tree: " + str(path))
                        z.write(path,path.relative_to(ROOT).as_posix())
            z.write(ROOT/"LICENSE","LICENSE")
            for row in inventory["files"]:
                if row["arch"]!=arch:
                    continue
                if cache:
                    data=(cache/row["name"]).read_bytes()
                else:
                    url="https://raw.githubusercontent.com/SherryPlatform/Microsoft.DirectX.Linux.Binaries/{}/{}".format(inventory["commit"],row["path"])
                    with urllib.request.urlopen(url, timeout=120) as response:
                        data=response.read()
                check_elf(data,arch,(3,))
                if digest(data)!=row["sha256"]:
                    raise ValueError("Runtime checksum mismatch: "+row["name"])
                z.writestr("lib/"+row["name"],data)
                meta["libraries"][row["name"]]=row["sha256"]
            if set(meta["libraries"])!={"libdxcore.so","libd3d12.so","libd3d12core.so"}:
                raise ValueError("Incomplete runtime manifest")
            data=probe.read_bytes()
            check_elf(data,arch,(2,3))
            z.writestr("guest/d3d12-compute",data)
            meta["probeSha256"]=digest(data)
            modules={}
            for path in sorted(pool.rglob("module.json")):
                entry=json.loads(path.read_text())
                if entry["arch"]!=arch:
                    raise ValueError("Mixed architecture pool")
                release=entry["release"]
                if (not re.fullmatch(r"[A-Za-z0-9][A-Za-z0-9._+-]*",release) or
                        entry["vermagic"].split()[0]!=release or entry["name"]!="dxgkrnl"):
                    raise ValueError("Invalid module metadata")
                data=(path.parent/"dxgkrnl.ko").read_bytes()
                check_elf(data,arch,(1,))
                if digest(data)!=entry["sha256"]:
                    raise ValueError("Module checksum mismatch")
                if release in modules:
                    prior=modules[release]
                    if any(prior[k]!=entry[k] for k in ("sha256","srcversion","vermagic")):
                        raise ValueError("Module collision for "+release)
                    prior["targets"].append(entry["target"])
                    continue
                entry["targets"]=[entry.pop("target")]
                modules[release]=entry
                z.writestr(f"prebuilt/{arch}/{release}/dxgkrnl.ko",data)
            if not modules:
                raise ValueError("Empty prebuilt pool")
            meta["kernels"]=[modules[k] for k in sorted(modules)]
            z.writestr("prebuilt/index.json",json.dumps(meta["kernels"],indent=2))
            z.writestr("manifest.json",json.dumps(meta,indent=2))
        with ZipFile(stage) as archive:
            if archive.testzip():
                raise ValueError("Bundle CRC failure")
        stage.replace(output/name)
    return output/name


def main():
    parser=argparse.ArgumentParser()
    parser.add_argument("--arch",required=True,choices=MACHINES)
    parser.add_argument("--version",required=True)
    parser.add_argument("--pool",type=Path,required=True)
    parser.add_argument("--probe",type=Path,required=True)
    parser.add_argument("--output-dir",type=Path,default=ROOT/"dist")
    parser.add_argument("--runtime-dir",type=Path)
    args=parser.parse_args()
    print(build(args.arch,args.version,args.pool,args.probe,args.output_dir,args.runtime_dir))


if __name__=="__main__":
    main()
