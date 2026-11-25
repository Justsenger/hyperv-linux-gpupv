# hyperv-linux-gpupv

为运行在 Windows Hyper-V（x64 与 ARM64）上的 Linux 虚拟机提供 GPU-PV 内核通道与计算层运行时部署方案。配合 [ExHyperV](https://github.com/Justsenger/ExHyperV) 或本仓宿主工具即可将宿主机分区显卡（单卡或多卡）接入可写的 `glibc` Linux 来宾，**宿主机无需安装 WSL**。

按宿主架构前往 [Releases](https://github.com/Justsenger/hyperv-linux-gpupv/releases) 下载对应部署包，并用同批 `SHA256SUMS` 校验：

- `linuxpv-bundle-x86_64-<version>.zip`（适用于 Windows x64 宿主与 `x86_64` Linux 虚拟机）
- `linuxpv-bundle-aarch64-<version>.zip`（适用于 Windows ARM64 宿主与 `aarch64` Linux 虚拟机）

---

## 目前的目标与状态（Phase 1：计算层交付版）

现阶段的核心目标是：**让尽可能多的主流 Linux 发行版在免繁琐配置的前提下，稳定获得可用的 GPU 算力（Compute Only）**。

- **当前主保能力**：`/dev/dxg` 内核设备通道、DXCore / D3D12 Compute、NVIDIA CUDA 与 `nvidia-smi`、OpenCL GPU 计算。
- **暂不作为本阶段发布门槛**：Linux 硬件视频编解码（NVENC / VA-API / FFmpeg）与桌面 3D 图形输出（Vulkan Dozen / OpenGL / X11 / Wayland）目前仅作为可选扩展（通过 `--with-video` 开关触发），历史视频回归记录保留在 [docs/2026-11-24-video-release.md](docs/2026-11-24-video-release.md)。
- **v0.1.0-rc1 当前实证基线**：
  - 双架构预编译池共包含 **284 个“架构 + 内核版本”组合**（`x86_64` 166 个，`aarch64` 118 个）。
  - 在无 `gcc`、`make` 与内核头文件的 Debian 12 `x86_64`（`6.1.0-56-amd64`）上，已实机通过 RTX 2060 + Intel Iris Xe 双卡同时接入、普通用户 D3D12 Compute（各 64/64）、CUDA 数值验证、Secure Boot 开启下 MOK 签名重启加载（签名告警为 0）以及重复安装与卸载清理。
  - 其余主流发行版构建清单、ARM64 编译包验证与完整日志参见 [COMPATIBILITY.md](COMPATIBILITY.md) 与 [artifacts/reports/phase1](artifacts/reports/phase1)。
  - **透明告知**：内核日志中部分来自用户态查询的 `-22` / `-2` 诊断返回值仍会记录（不影响计算与功能稳定性，未过滤日志），且 ARM64 与跨厂商大规模真机扩测正在同步补齐中。

---

## 适配范围与系统条件

安装器在虚拟机内不按发行版名字设白名单，而是采用**“预编译模块优先直装 + 源码/DKMS 自动兜底”**的双轨机制。

### 1. 支持的 Linux 来宾系统

只要目标 Linux 来宾满足以下基础条件，即可部署使用：

- **C 运行库与文件系统**：标准可写入根目录的 **`glibc` 发行版**（同时兼容常见 systemd 发行版及具备可用 `udev` 守护进程的非 systemd 系统）。
- **内核接口**：具备页固定接口（如带向后移植的 RHEL/EL8 `4.18` 及 `5.10` ~ `7.4` 主流内核）及 Hyper-V 虚拟 PCI 总线驱动 `pci_hyperv`。
- **免编译直装条件**：若目标虚拟机内核命中部署包 `prebuilt/` 中收录的 284 个内核之一（涵盖 Ubuntu 20.04 HWE~26.10、Debian 11~Sid、Rocky / Alma 8~10、CentOS Stream 9~10、Oracle UEK/RHCK、Fedora 41~Rawhide、Anolis、openEuler x64、OpenCloudOS 9、Azure Linux、openSUSE Leap / Tumbleweed / Slowroll、Arch 系列、Manjaro、CachyOS、Kali、deepin、Kylin、Mint、Pop!_OS、TrueNAS、OMV、Devuan、Gentoo 等对应构建版本，完整目录见 [发行版与内核清单](artifacts/reports/actions-native-matrix.md) 与 [targets/matrix.json](targets/matrix.json)），来宾**不需要安装 `gcc`、`make` 或内核头文件**，仅需 `python3`、`kmod`、`udev` 即可完成安装。
- **源码/DKMS 自动兜底**：若使用滚动更新最新小版本或尚未进入预编译池的衍生内核（例如基于 Debian 12 `glibc` 的飞牛 fnOS 等自定义内核版本），安装器会自动回落到包内 `kernel/` 源码编译。此时目标来宾需先装好与当前运行内核精确匹配的 `linux-headers` / `kernel-devel`、`make` 与对应 `gcc` / `clang`。
- **Secure Boot 兼容**：未启用 Secure Boot 的来宾会跳过签名步骤直接完成安装。已启用 Secure Boot 的来宾仅需 `shim`、`mokutil` 与 `openssl`，由工具链内置独立签名器完成本机 MOK 签名，**即使没有内核头文件目录也能签署预编译模块**。

### 2. 支持的宿主显卡

- 协议与安装器**不限制 GPU 厂商**，支持同一台虚拟机挂载 **1 张或多张不同厂商显卡**。
- 前提是宿主机对应物理显卡当前安装的 Windows 驱动包中包含 GPU-PV / WSL Linux UMD（`.so` 用户态组件）。部分过老架构或历史驱动分支（如老旧 Intel 27.x 等尚未携带 Linux 运行库的驱动）无法用于 Linux 算力部署。
- 当前已提供充分真机计算证据的为 NVIDIA（RTX 2060）与 Intel（Iris Xe），AMD 与高通 Adreno ARM64 正在补齐完整实机验证。

### 3. 明确不支持的范围

为控制第一阶段质量与边界清晰，以下场景会在前置体检阶段拦截或暂不支持：

- 使用 `musl` 等非 `glibc` 运行库的发行版（如 **Alpine Linux**）。
- 只读根目录或不可变文件系统发行版（如 **NixOS**、**Fedora CoreOS / Silverblue ostree**）。
- 缺少 `pin_user_pages_fast` / `unpin_user_pages` 页固定接口的老旧内核（如未升级 HWE 的原生 **Ubuntu 20.04 GA `5.4`**、**OpenCloudOS 8**）。
- 上游自身未包含 Hyper-V 架构头文件或未导出 VMBus 符号的特定 ARM64 内核（如 Debian 11 ARM64、openEuler ARM64、Amazon Linux 2023 ARM64、Arch Linux ARM 等，具体原因见 [发行版与内核清单](artifacts/reports/actions-native-matrix.md)）。

---

## 快速安装

### 方式 A：搭配 ExHyperV 使用（推荐规划流程）

1. 在 **ExHyperV** 中为目标虚拟机完成 GPU 分区分配与 MMIO 配置。
2. 在界面选择从本仓库 [Releases](https://github.com/Justsenger/hyperv-linux-gpupv/releases) 下载好的对应架构部署包 ZIP。
3. ExHyperV 将部署包与本机选中物理显卡的宿主驱动合成为 `GPUPV` 卷标 UDF 光盘并挂载到虚拟机。
4. 进入 Linux 虚拟机打开终端，执行光盘安装命令即可全自动完成部署。

### 方式 B：使用本仓 PowerShell 宿主工具生成光盘 / SSH 部署

准备前提：来宾中提前确认已安装 `python3`、`kmod`、`udev`，并将需要调用 GPU 的普通用户加入 `video` 组后重新登录。开启 Secure Boot 的来宾另需准备 `shim`、`mokutil`、`openssl`。

在 Windows 宿主管理员 PowerShell 7.4+ 中执行（按本机实际情况替换包路径、显卡名与虚拟机名）：

```powershell
./host/gpupv-host.ps1 list
$b = './linuxpv-bundle-x86_64-v0.1.0-rc1.zip'
$cards = 'NVIDIA GeForce RTX 2060','Intel(R) Iris(R) Xe Graphics'
./host/gpupv-host.ps1 doctor -Bundle $b
./host/gpupv-host.ps1 iso -Bundle $b -Gpu $cards -Output ./gpu.iso -VMName '你的虚拟机'
```

进入 Linux 来宾后运行：

```sh
sudo mkdir -p /mnt/gpupv && sudo mount -o ro -L GPUPV /mnt/gpupv && sudo sh /mnt/gpupv/guest/setup
```

若光盘已经手动挂载到 `/mnt/gpupv`，直接执行 `sudo sh /mnt/gpupv/guest/setup`。若首次启用 Secure Boot 且本机尚未登记 MOK，请按屏幕给出的 `sudo mokutil --import ...` 命令设置一次性密码，重启并在蓝底 MOK Manager 界面选择 `Enroll MOK` 确认，回到系统后重新挂载光盘执行安装即可（同一台虚拟机只需录入一次）。

若来宾已配置 SSH 公钥与免交互 `sudo`，也可直接通过 `./host/gpupv-host.ps1 push -Gpu $cards -Bundle $b -Destination user@vm` 推送并安装。

### 常见发行版前置提醒

- **Ubuntu 等云镜像缺失 `pci_hyperv`**：若安装自检提示未枚举虚拟 PCI 设备或缺少 `pci_hyperv`，请先安装匹配当前运行内核的 `linux-modules-extra-$(uname -r)` 并加载 `pci_hyperv`。
- **openSUSE Leap / SUSE 系**：请确认运行内核与仓库内的 `kernel-default-devel` 版本一致，且按 SUSE 官方策略允许加载自签名外部模块。
- **Arch 云镜像与 Secure Boot**：若默认 GRUB 启动链未接入 `shim`，需切换为受信任 `shim` + 签名 UKI 以使 MOK 证书生效。

---

## 验证与卸载

以 `video` 组普通用户身份运行检查与算力验收（默认仅测算力，不测视频）：

```sh
gpupv-guest doctor
gpupv-guest verify
```

`verify` 会打开 `/dev/dxg`，逐卡验证所有硬件 DXCore / D3D12 计算适配器（64 项计算回读），并在检测到 NVIDIA 工具 / CUDA / GPU OpenCL ICD 时补充对应算力校验。如需实验性触发视频编解码验证，可附加 `--with-video`（详见 [docs/2026-11-24-video-release.md](docs/2026-11-24-video-release.md)）。

彻底卸载（保留管理员在固件中登记的 MOK 密钥供后续使用）：

```sh
sudo gpupv-guest uninstall
```

---

## 未来路线规划（Roadmap）

1. **阶段一完善与全矩阵扩测（进行中）**
   - 补齐 ARM64 实机（高通骁龙 Adreno）及更多主流 x64 / ARM64 发行版、AMD 与多品牌混插场景下的算力真机实证。
   - 完善 ExHyperV 图形化界面中的部署包下载引导、版本/架构自动校验、UDF 光盘合成挂载与一键命令拷贝集成。
2. **阶段二：宿主驱动超精度提取与光盘减重**
   - 通过全厂商多代驱动静态剖析与运行期文件读取采样，在保证不破坏同厂未测新型号的前提下，在 ExHyperV 合盘阶段精细剔除冗余 Windows PE 二进制与无关子包，大幅缩小驱动光盘体积。
3. **阶段三：硬件视频编解码与桌面 3D 加速**
   - 面向跨发行版推进 Mesa D3D12 VA-API 硬件编解码（H.264 / HEVC / VP9 / AV1）稳定性治理，并跟进 Vulkan / OpenGL / Wayland 桌面图形通路验证。

---

## 许可说明与延伸文档

- 微软三份 DirectX Linux 运行库（`libdxcore.so`、`libd3d12.so`、`libd3d12core.so`）依据 [host/wsl-runtime.json](host/wsl-runtime.json) 固定提交与摘要写入各架构 Release 部署包，公开源码包（`hyperv-linux-gpupv-source.zip`）仅包含纯源码、工具脚本与报告文档。宿主 Windows 显卡驱动及微软二进制均各自适用原厂专有许可。
- 相关技术文档：
  - [ExHyperV 合盘契约规范](docs/EXHYPERV-BUNDLE-CONTRACT.md)
  - [双架构模块构建、定制内核扩展与发布说明](docs/COMPUTE-BUILD.md)
  - [兼容性矩阵与实测证据](COMPATIBILITY.md)
  - [第一阶段完整测试原始报告](artifacts/reports/phase1)
  - [历史视频编解码回归说明](docs/2026-11-24-video-release.md)
