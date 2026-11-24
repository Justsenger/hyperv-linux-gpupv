"""Plan native Actions jobs and export kernel modules built in distro containers."""
import argparse
import hashlib
import json
import platform
import re
import subprocess
from pathlib import Path
from urllib.parse import urlsplit

ROOT=Path(__file__).resolve().parents[1]
RUNNERS={"x86_64":"ubuntu-24.04","aarch64":"ubuntu-24.04-arm"}


def main():
    parser=argparse.ArgumentParser()
    parser.add_argument("--matrix",type=Path,default=ROOT/"targets/matrix.json")
    parser.add_argument("--plan",action="store_true")
    parser.add_argument("--target")
    parser.add_argument("--arch",choices=RUNNERS)
    parser.add_argument("--output",type=Path,default=ROOT/"out")
    args=parser.parse_args()
    targets=json.loads(args.matrix.read_text())["targets"]
    jobs=[]
    for t in targets:
        if not re.fullmatch(r"[a-z0-9][a-z0-9.-]*",t["id"]):
            raise ValueError("Invalid target")
        for arch in t["arch"]:
            jobs.append(dict(target=t["id"],arch=arch,runner=RUNNERS[arch]))
    if len({(j["target"],j["arch"]) for j in jobs})!=len(jobs):
        raise ValueError("Duplicate target")
    if args.plan:
        print(json.dumps({"include":jobs},separators=(",",":")))
        return
    if platform.machine()!=args.arch:
        raise ValueError("Native runner required")
    t,=[t for t in targets if t["id"]==args.target and args.arch in t["arch"]]
    debarch="amd64" if args.arch=="x86_64" else "arm64"
    header=t.get("headers",{})
    if header and (urlsplit(header["url"]).scheme!="https" or not re.fullmatch("[0-9a-f]{64}",header["sha256"]) or header["format"] not in ("deb","rpm","tar")):
        raise ValueError("Expected HTTPS header URL with format and SHA-256")
    packages=t.get("packagesByArch",{}).get(args.arch,t["packages"])
    env={"TARGET_ARCH":args.arch,"FAMILY":t["family"],"PACKAGES":" ".join(p.format(debarch=debarch) for p in packages),
         "REPO_KEY":t.get("keyFingerprint",""),"ARCHIVE":"yes" if t.get("archive") else "no","REPO_LINE":t.get("repo",""),
         "HEADER_URL":header.get("url",""),"HEADER_SHA":header.get("sha256",""),"HEADER_FORMAT":header.get("format","")}
    out=args.output.resolve()/args.target
    out.mkdir(parents=True,exist_ok=False)
    cmd=["docker","run","--rm","-v","/etc/ssl/certs/ca-certificates.crt:/tmp/host-ca.pem:ro",
         "-e","http_proxy","-e","https_proxy","-e","HTTP_PROXY","-e","HTTPS_PROXY","-v",f"{ROOT}:/source:ro","-v",f"{out}:/out"]
    for k,v in env.items():
        cmd.extend(["-e",k+"="+v])
    # Let the runner write module metadata after the root-owned container exits.
    subprocess.run(cmd+[t["image"],"sh","-ec",'sh /source/tests/build-kernel-target && chmod -R a+rwX /out'],check=True)
    for ko in out.glob("*/dxgkrnl.ko"):
        data=ko.read_bytes()
        if data[:6]!=b"\x7fELF\x02\x01" or int.from_bytes(data[18:20],"little")!={"x86_64":62,"aarch64":183}[args.arch]:
            raise ValueError("Module ELF mismatch")
        entry={"arch":args.arch,"target":t["id"],"release":ko.parent.name,"name":"dxgkrnl",
               "vermagic":(ko.parent/"vermagic").read_text().strip(),"srcversion":(ko.parent/"srcversion").read_text().strip(),
               "sha256":hashlib.sha256(data).hexdigest()}
        (ko.parent/"module.json").write_text(json.dumps(entry,indent=2)+"\n")
        print(json.dumps(entry))


if __name__=="__main__":
    main()
