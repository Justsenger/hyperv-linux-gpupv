"""Index completed Hyper-V runs without promoting partial results."""
from pathlib import Path
import json
import re

reports = Path(__file__).resolve().parents[1] / "artifacts" / "reports"


def read(path):
    return path.read_text(encoding="utf-8-sig", errors="replace") if path.is_file() else ""


def link(folder, filename, label):
    if (folder / filename).is_file():
        return f"[{label}]({folder.name}/{filename})"
    return "—"


def guest_run(folder, vendor):
    env = read(folder / "environment.txt")
    kernel = re.search(r"^Linux \S+ (\S+)", env, re.M)
    boot = read(folder / "installed-boot-after.txt").splitlines()
    old_boot = read(folder / "installed-boot-before.txt").strip()
    access = read(folder / "access.txt")
    workload = read(folder / "workload.txt") or read(folder / "independent-nvidia.txt")
    nvidia = all(f"7 * {value} + 3 = {7 * value + 3}" in workload for value in (5, 19, 127))
    frames = re.findall(r"^0,\s*\d+,\s*\d+,\s*\d+,\s*\d+,\s*[a-f0-9]{32}\s*$", workload, re.M)
    hardware = "—"
    if vendor == "NVIDIA" and workload:
        pieces = ["CUDA 数值通过" if nvidia else "CUDA 未证实"]
        pieces.append(f"NVENC/CUVID {len(frames)} 帧" if len(frames) == 15 else "编解码未通过")
        hardware = "，".join(pieces)
    if vendor == "Intel" and workload:
        if "CreateAdapterList(CORE_COMPUTE)" in workload or "Intel OpenCL exit=" in workload:
            pieces = []
            if "matched=64/64" in workload:
                pieces.append("D3D12 Compute 64/64")
            if "verified 32 OpenCL results" in workload:
                pieces.append("OpenCL 32/32")
            if not pieces:
                pieces.append("计算未证实")
            if "H.264 intra hardware encode: 15 decodable frames" in workload and "VP9 hardware decode: 15/15 frames match" in workload:
                pieces.append("H.264 硬编、VP9 硬解各 15 帧")
            elif "isolated_product_exit=0" in read(folder / "isolated-intel-va.txt"):
                pieces.append("隔离运行库 H.264 硬编、VP9 硬解各 15 帧")
            else:
                pieces.append("VA-API 硬件编解码 15 帧" if len(frames) == 15 and "h264_vaapi" in workload else "视频未通过")
            hardware = "，".join(pieces)
        elif re.search(r"^OpenGL renderer string: D3D12.*Intel", workload, re.M | re.I):
            hardware = "Intel D3D12 渲染器"
        elif "llvmpipe" in workload:
            hardware = "仅见软件设备或硬件上下文失败"
        else:
            hardware = "硬件工作负载未通过"
    clean = read(folder / "clean-after-reboot.txt") or read(folder / "uninstall-after-reboot.txt")
    repeat = (folder / "install-repeat.txt").is_file() and "preflight OK" in read(folder / "install-repeat.txt")
    lifecycle = " / ".join((
        "重启权限通过" if len(boot) >= 2 and old_boot and old_boot != boot[-1] and "crw-rw" in access else "重启权限未证实",
        "重复安装通过" if repeat and boot else "重复安装未证实",
        "卸载重启通过" if "managed_paths_clean" in clean else "卸载未证实",
    ))
    result_path = folder / "result.json"
    strict = "未完成"
    if result_path.exists():
        strict = "通过" if json.loads(read(result_path)).get("passed") is True else "未通过"
    return kernel[1] if kernel else "—", lifecycle, hardware, strict


def main():
    header = ["# Hyper-V 端到端试验索引", "", "每行对应一次真实虚拟机试验。相同组合的重试各自保留记录。", "",
              "|基座 / GPU|运行内核|安装与卸载|普通用户工作负载|严格验收|原始记录|", "|---|---|---|---|---|---|"]
    rows = []
    indexed = set()
    for wrapper in sorted(reports.glob("e2e-*")):
        if not wrapper.is_dir():
            continue
        match = re.fullmatch(r"e2e-(.+)-(Intel|NVIDIA)-([a-f0-9]{8})", wrapper.name)
        if not match:
            continue
        base, vendor, prefix = match.groups()
        dirs = sorted(reports.glob(f"gpupv-test-{prefix}*-*"))
        detail = link(wrapper, "outcome.txt", "结果") + " · " + link(wrapper, "dependencies.txt", "依赖")
        if not dirs:
            rows.append((base, vendor, "—", "未取得", "未取得", "未通过或未完成", detail))
            continue
        for folder in dirs:
            indexed.add(folder)
            kernel, lifecycle, workload, strict = guest_run(folder, vendor)
            detail_links = detail + " · " + link(folder, "workload.txt", "工作负载") + " · " + link(folder, "dmesg-after-workload.txt", "内核日志")
            rows.append((base, vendor, kernel, lifecycle, workload, strict, detail_links))
    for folder in sorted(reports.glob("gpupv-test-*-*")):
        if folder in indexed or not (folder / "environment.txt").is_file():
            continue
        env = dict(re.findall(r'^([A-Z_]+)="?([^"\n]+)"?$', read(folder / "environment.txt"), re.M))
        base = env.get("ID", "unknown") + "-" + env.get("VERSION_ID", "unknown")
        sample = read(folder / "workload.txt") or read(folder / "independent-nvidia.txt")
        if "NVIDIA" in sample:
            vendor = "NVIDIA"
        elif "Intel" in sample:
            vendor = "Intel"
        else:
            continue
        rows.append((base, vendor, *guest_run(folder, vendor), f"[试验记录]({folder.name}/)"))
    for base, vendor, kernel, lifecycle, workload, strict, detail in sorted(rows):
        header.append(f"|{base} / {vendor}|{kernel}|{lifecycle}|{workload}|{strict}|{detail}|")
    (reports / "e2e-index.md").write_text("\n".join(header) + "\n", encoding="utf-8")


if __name__ == "__main__":
    main()

