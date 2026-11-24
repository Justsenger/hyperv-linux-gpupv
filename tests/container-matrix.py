#!/usr/bin/env python3
"""Build the vendored module against distribution-packaged kernel headers."""
import argparse
import hashlib
import json
from pathlib import Path
import shutil
import subprocess
import sys
import time

DEBIAN = """for f in /etc/apt/sources.list /etc/apt/sources.list.d/*.sources; do test ! -f "$f" || sed -i s,http://,https://,g "$f"; done
printf '%s\n' 'Acquire::https::CaInfo "/tmp/gpupv-ca.pem";' > /etc/apt/apt.conf.d/90gpupv-build-ca
apt-get -o Acquire::Languages=none -o APT::Update::Error-Mode=any update
DEBIAN_FRONTEND=noninteractive apt-get -y --no-install-recommends install make gcc kmod {headers}"""
RPM = """dnf -y --setopt=install_weak_deps=False install make gcc kmod elfutils-libelf-devel kernel-devel"""
SUSE = """zypper --non-interactive refresh
zypper --non-interactive install --no-recommends gcc make kmod gawk kernel-default-devel kernel-devel libelf-devel"""
ARCH = """pacman -Syu --noconfirm --needed gcc make kmod linux-headers libelf"""
CASES = {}
for release in ("20.04","22.04","24.04","26.10"):
    CASES[f"ubuntu-{release}"] = (f"ubuntu:{release}",DEBIAN.format(headers="linux-headers-generic"))
for release in ("11","12","13"):
    CASES[f"debian-{release}"] = (f"debian:{release}",DEBIAN.format(headers="linux-headers-amd64"))
for distro,image in (("rocky","quay.io/rockylinux/rockylinux"),("alma","almalinux")):
    for release in ("8","9"):
        CASES[f"{distro}-{release}"] = (f"{image}:{release}",RPM)
for release in ("43","44"):
    CASES[f"fedora-{release}"] = (f"quay.io/fedora/fedora:{release}",RPM)
CASES.update({
    "arch":("archlinux:latest",ARCH),
    "arch-lts":("archlinux:latest",ARCH.replace("linux-headers","linux-lts-headers")),
    "ubuntu-20.04-hwe":("ubuntu:20.04",DEBIAN.format(headers="linux-headers-generic-hwe-20.04")),
    "debian-11-base":("debian:11",DEBIAN.format(headers="linux-headers-amd64/bullseye linux-compiler-gcc-10-x86/bullseye")),
    "debian-11-archive":("debian:11",
        "printf '%s\\n' 'deb https://deb.debian.org/debian bullseye main' "
        "'deb [check-valid-until=no] https://snapshot.debian.org/archive/debian-security/20260805T000000Z/ "
        "bullseye-security main' > /etc/apt/sources.list\n"+DEBIAN.format(headers="linux-headers-amd64")),
    "leap":("opensuse/leap:15.6",SUSE),
    "tumbleweed":("opensuse/tumbleweed:latest",SUSE),
    "anolis-23":("openanolis/anolisos:23",RPM),
    "openeuler":("openeuler/openeuler:24.03-lts",RPM),
})
BUILD = """
cp -R /source /tmp/kernel
found=0
for dir in /lib/modules/*/build /usr/src/kernels/*; do
    test -f "$dir/Makefile" || continue
    dir=$(readlink -f "$dir")
    echo "HEADER_TREE=$dir"
    sh /tmp/kernel/build "$dir"
    ko=/tmp/kernel/drivers/hv/dxgkrnl/dxgkrnl.ko
    modinfo "$ko"
    sha256sum "$ko"
    found=1
    break
done
test "$found" = 1
"""


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("cases", nargs="*", help="Default: all targets")
    parser.add_argument("--engine",default="docker")
    args = parser.parse_args()
    engine = shutil.which(args.engine)
    if not engine:
        sys.exit(f"Missing {args.engine}")
    root = Path(__file__).resolve().parents[1]
    reports = root / "artifacts/reports/compile-matrix"
    reports.mkdir(parents=True,exist_ok=True)
    sources = hashlib.sha256()
    for path in sorted((root/"kernel").rglob("*"),key=lambda p:p.as_posix()):
        if path.is_file():
            sources.update(path.relative_to(root).as_posix().encode()+b"\0")
            sources.update(hashlib.sha256(path.read_bytes()).digest())
    failures = 0
    for name in args.cases or CASES:
        image,prepare = CASES[name]
        with (reports / f"{name}.log").open("w") as f:
            print(f"image={image} unix_time={int(time.time())} sources_sha256={sources.hexdigest()}",file=f,flush=True)
            cmd = [engine,"run","--rm","--network=host","-v","/etc/ssl/certs/ca-certificates.crt:/tmp/gpupv-ca.pem:ro","-e","http_proxy","-e","https_proxy","-e","HTTP_PROXY","-e","HTTPS_PROXY","-v",f"{root / 'kernel'}:/source:ro",
                   image,"sh","-ec","cat /etc/os-release\n"+prepare+"\n"+BUILD]
            rc = subprocess.run(cmd,stdout=f,stderr=subprocess.STDOUT).returncode
            print(f"exit={rc}",file=f)
        result = {"image":image,"passed":rc==0,"exit":rc,"sources_sha256":sources.hexdigest()}
        (reports/f"{name}.json").write_text(json.dumps(result)+"\n")
        print(name,result,flush=True)
        failures += bool(rc)
    return bool(failures)


if __name__=="__main__":
    if any(arg in sys.argv for arg in ("--plan","--arch","--matrix","--target")):
        import runpy
        runpy.run_path(str(Path(__file__).with_name("native-matrix.py")),run_name="__main__")
    else:
        sys.exit(main())

