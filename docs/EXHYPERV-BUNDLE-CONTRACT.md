# ExHyperV 合盘契约 v1

每个 Release 提供 linuxpv-bundle-x86_64-VERSION.zip、linuxpv-bundle-aarch64-VERSION.zip、纯源码 ZIP 与 SHA256SUMS。先按清单校验完整 ZIP。Windows OSArchitecture 的 X64 对应 x86_64，Arm64 对应 aarch64。检查 ZIP 根的 manifest.json，拒绝不匹配的 arch 或不支持的 schemaVersion。

```json
{
  "schemaVersion": 1, "arch": "aarch64", "version": "v1.0.0",
  "libraries": {"libdxcore.so":"<sha256>", "libd3d12.so":"<sha256>", "libd3d12core.so":"<sha256>"},
  "probeSha256":"<sha256>",
  "kernels":[{"arch":"aarch64","release":"<uname -r>","name":"dxgkrnl","vermagic":"<modinfo -F vermagic>","srcversion":"<modinfo -F srcversion>","sha256":"<sha256>","targets":["debian-12"]}]
}
```

将 ZIP 解到新的暂存目录。保留 lib/、kernel/、guest/、prebuilt/index.json、prebuilt/ARCH/RELEASE/dxgkrnl.ko 和 LICENSE。prebuilt/index.json 与 manifest.kernels 相同。ELF 为小端 64 位，x86_64 的 e_machine 为 62，aarch64 为 183；模块为 ET_REL，运行库为 ET_DYN，探针可为 ET_EXEC 或 ET_DYN。

对每个已分配的 GPU，读取实际 PnP 驱动软件键、主和伴随 INF，将原厂目录完整复制至 drivers/PackageDir。带 NTamd64 或 NTarm64 装饰的 INF Directory/CopyFiles 节按宿主架构筛选。lib/ 采用 INF 的 lxss 别名，若同包的原文件名被 INF 用作加载器别名，真实厂商文件仍保留在 drivers/PackageDir 下。其余 Linux ELF（包括组件驱动）按文件名导出。合并不同显卡、伴随组件或微软运行库时，已有同名文件只接受相同 SHA-256，冲突立即报错。按 ELF 头选择架构，不能从 INF 文件夹中的 amd64 或 arm64 字符串推断文件架构。

在根目录写 device.json。每个对象描述一张已绑定的物理 GPU，同型号重复时以完整 PnP 设备标识选卡。

```json
{"schemaVersion":1,"arch":"x86_64","adapters":[{"device":"PCI\\VEN_8086&DEV_9A49...","name":"Intel Iris Xe","version":"32.0.101.6876","package":"iigd_dch.inf_amd64_..."}]}
```

生成卷标 GPUPV 的 UDF 光盘，校验目标 VM 的 GPU 分区集合与用户选择相同后挂载。PowerShell 示例：

```powershell
./host/gpupv-host.ps1 list
./host/gpupv-host.ps1 iso -Bundle .\linuxpv-bundle-x86_64-v1.0.0.zip -Gpu @('NVIDIA GeForce RTX 2060','Intel(R) Iris(R) Xe Graphics') -Output .\local.iso -VMName 'your-vm'
```

来宾单行安装：

```sh
sudo mkdir -p /mnt/gpupv && { mountpoint -q /mnt/gpupv || sudo mount -o ro "$(sudo blkid -L GPUPV)" /mnt/gpupv; } && sudo sh /mnt/gpupv/guest/setup
```

已录入 MOK 或关闭 Secure Boot 时可一次完成。首次录入由管理员在 shim 菜单确认。安装后以 video 组普通用户执行 `gpupv-guest verify`，可选视频步骤使用 `--with-video`。卸载执行 `sudo gpupv-guest uninstall`。光盘上的私有宿主 UMD 仅用于该宿主的部署；公开源码归档与按架构发布的微软运行库部署包分别生成。

## 接入与验收

Windows Dev Kit 2023 的新建 ARM64 来宾在 WMI 中读回高位基址 65024 MiB、高位大小 512 MiB、低位大小 512 MiB。以默认高位窗口结束地址 `E = base + size` 计算，实测可用配置为 `HighMmioGapBase = E − 32768`、`HighMmioGapSize = 32768 − 1024`、`LowMmioGapSize = 3584`，各值以 MiB 计。在这台宿主上高位窗口覆盖 [32768, 64512) MiB，顶部保留 1024 MiB，Adreno 计算回读 64/64。[WMI 与计算记录](../artifacts/reports/arm64-expanded/mmio-trace/sampling.md)

同一 `uname -r` 和 vermagic 可能对应不同的发行版内核 ABI。预编译模块还会与当前内核随附的 Hyper-V 模块比对共同引用的符号 CRC。发现差异后使用该来宾的内核头文件进行源码构建。[Ubuntu GA 与 HWE 对照](../artifacts/reports/arm64-expanded/ubuntu-26.04-ga/abi-comparison.txt)

本机驱动 30.0.4122.4000 在一次普通用户 D3D12 计算中成功打开三个微软运行库及两个 Qualcomm ELF 库。此结果仅覆盖这次计算的用户态路径。提取范围应随宿主驱动与工作负载验证。[实际打开的文件与原始 strace](../artifacts/reports/arm64-expanded/mmio-trace/sampling.md)

ExHyperV 先按目标来宾架构选择 ZIP，用同一发行版本的 SHA256SUMS 校验整包，再校验 manifest 中的每个 SHA-256。合盘时保留 guest/d3d12-compute，设置 Linux 可执行权限由安装器完成。可用 `python3 tests/check-bundle.py <zip> <arch>` 在解包前执行与 CI 一致的契约检查。

来宾按 uname -m 和 uname -r 精确匹配模块，并用 modinfo 复核 name、vermagic、srcversion。匹配时只需 Python、kmod、udev 等运行工具，可在无 gcc、make 和 headers 的系统安装。未命中时从 kernel/ 编译，需要对应内核头与编译器。Secure Boot 已关闭时跳过 MOK；开启时使用本地受信任密钥和 OpenSSL CMS 签名预编译模块。首次信任需管理员完成 MOK 录入。

纯算力验收以普通用户执行 `gpupv-guest verify` 的退出码、硬件适配器标识及数量、逐卡数值回读为准。合盘时保留完整的宿主 PnP 实例 ID。PCI 使用十六进制厂商和设备号。本机 Adreno 的 ACPI 标识 `VEN_QCOM&DEV_0636` 对应 DXCore 的 `4d4f4351:36333630`。ARM64 本地版同时检查这两个 32 位值。Debian x86_64 双卡已有 D3D12、CUDA 和 OpenCL 数值证据，ARM64 Adreno 已实测 D3D12。[双卡原始输出](../artifacts/reports/phase1/final-ssh/compute.txt) · [Adreno 签名重启后的原始输出](../artifacts/reports/arm64-devkit-2023/signed-reboot.txt)

本次成品 UDF 合盘、Secure Boot 受信任签名重启和卸载复核见[成品兼容性记录](../COMPATIBILITY.md)及[卸载后重启证据](../artifacts/reports/ci-bundle-ca173d3/clean.txt)。
