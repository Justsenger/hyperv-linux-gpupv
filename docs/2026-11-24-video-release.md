# hyperv-linux-gpupv

将一张 Hyper-V 分区显卡对应的 Windows 驱动和 DirectX Linux 运行库打包，供 Linux 虚拟机离线安装或通过 SSH 部署。当前为候选版。本轮仅验收内核通道、GPU 计算和硬件视频编解码。RTX 2060 和 Iris Xe 的逐项结果、内核错误与签名记录见[冻结介质真机矩阵](../artifacts/reports/2026-11-24/final-matrix.md)和[兼容性记录](../COMPATIBILITY.md)。

1. 在管理员 PowerShell 7.4+ 中运行 `./host/gpupv-host.ps1 list`，记下显卡名称，运行 `./host/gpupv-host.ps1 doctor` 检查 WSL 库。
2. 在已绑定这张显卡的 Gen2 虚拟机内准备 shim、mokutil、openssl、glibc、Python 3（本次来宾最低实测 3.6.15）、gcc、make、kmod、udev 和运行内核的精确版本头文件。在宿主运行 `./host/gpupv-host.ps1 iso -Gpu 'NVIDIA GeForce RTX 2060' -Output gpu.iso`。指定 `-VMName <目标虚拟机名称>` 可在生成后直接挂载。也可将同一条命令中的 `iso` 改成 `pack`、输出文件改为 `gpu.tar`。
3. 假设光盘挂载于 `/mnt`，执行 `sudo sh /mnt/guest/setup`。若首次安装提示录入公钥，执行提示中的 `sudo mokutil --import <证书路径>`，设置一次性密码，重启后在 MOK Manager 选择 Enroll MOK 并确认，返回 Linux 后重新执行安装。安装成功后重启，以 video 组普通用户执行 `gpupv-guest verify`。卸载命令为 `sudo gpupv-guest uninstall`。

SSH 已配置公钥及免交互 sudo 时，第二、三步的安装可用 `./host/gpupv-host.ps1 push -Gpu 'NVIDIA GeForce RTX 2060' -Destination user@vm` 完成。NVIDIA 的 verify 会执行 CUDA 计算、NVENC 编码和 CUVID 解码，需要来宾自带支持这些功能的 FFmpeg。Intel 计算验收使用 D3D12 Compute，或有 Intel GPU ICD 时使用 OpenCL。D3D12 探针编译需要支持 C++17 的 g++。源码包内含 MIT 许可的 DirectX-Headers 头文件。Intel 视频验收通过 Mesa D3D12 VA-API 用恒定码率、受限基线和全 I 帧编码 H.264，独立验证码流可解出 15 帧，再用硬件解码 VP9 并校验 15 帧。需要 vainfo、带 libvpx 的 FFmpeg 和可访问的 DRM 节点。SSH 安装完成后自动以登录用户执行 `gpupv-guest check`。所有来宾安装命令均使用包内源码。

构建源码工具包运行 `python build.py`。公开压缩包不含 Windows 运行库与厂商驱动。

本地候选产物位于 `dist/2026-11-24/`。先在产物目录运行 `sha256sum -c SHA256SUMS`，或在 PowerShell 中用 `Get-FileHash .\irisxe-x64.iso` 与清单对应行核对。两张卡各有一份 UDF 光盘和一份 SSH 部署 tar。带厂商运行库的产物用于本地部署，公开源码对应 `hyperv-linux-gpupv-source.zip`。

在已部署的 Intel 来宾中，可从源码包运行 `sh tests/check-intel-video-profiles`，单独检查 VP9 硬解码及可用的 H.264、HEVC 硬编码入口。VP9 通过条件是全部 15 帧硬件回读结果与独立参考解码一致。H.264 或 HEVC 编码通过条件是产生能实际解出 15 帧的码流。[独立视频测试原始记录](../artifacts/reports/2026-11-24/matrix.md)

若本机 Mesa 缺少 H.264 编码入口，可将同批本地交付的 `ffmpeg-va-ubuntu24-x64.tgz` 复制到来宾。以下命令以普通用户解包到独立目录并只为本次体检选用该运行库。该 x64 文件含 Ubuntu 24.04 的 FFmpeg、vainfo、Mesa 和依赖，来源包版本在归档的 `packages` 中。

```sh
echo '5de76a5e106be82bbd610ff0af3b200779333f1c73cee8aa0fa16f3bc1c0a0d7  ffmpeg-va-ubuntu24-x64.tgz' | sha256sum -c - &&
  va_dir=$(mktemp -d "$HOME/gpupv-va.XXXXXXXX") &&
  tar -xzf ffmpeg-va-ubuntu24-x64.tgz -C "$va_dir" &&
  gpupv-guest verify --va-runtime "$va_dir"
```

如果 RTX 2060 来宾的 FFmpeg 缺少 `h264_nvenc` 或 `h264_cuvid`，同一份已校验、解包的 x64 运行库也可用于 NVIDIA。Fedora 44 在该配置下完成了 H.264 硬件往返。以普通用户运行以下命令，依次读取显存和驱动版本、计算三个 CUDA 结果、编码并解码 15 帧。[Fedora 44 原始负载](../artifacts/reports/gpupv-test-951008680583407685e5db901ea9b321-295d9b7b/workload.txt)

```sh
gpupv-guest check &&
  python3 /opt/hyperv-linux-gpupv/guest/cuda-compute.py 'NVIDIA GeForce RTX 2060' &&
  PATH="$va_dir:$PATH" sh /opt/hyperv-linux-gpupv/guest/verify-codec
```

`sudo gpupv-guest uninstall` 清理本工具的模块、DKMS 注册、运行库链接、设备规则和开机加载配置。来宾的本地签名密钥及管理员在固件中登记的 MOK 会保留，可供系统内核更新或其他已签名组件使用。Arch 的签名 UKI 也可能依赖同一证书。

Rocky 9 的已测官方内核关闭了 `CONFIG_DRM_VGEM`。该内核可直接使用 Iris Xe 计算。视频通过的配置还需要与运行内核匹配的受信任 VGEM 模块和上述隔离 VA 环境。测试机在一次启动中加载该模块，标准安装器仅管理 dxgkrnl。[Rocky 9 对照结果与源码版本](../COMPATIBILITY.md)

### 无 WSL 的宿主机

在管理员 PowerShell 中执行一次 `./host/gpupv-host.ps1 fetch-wsl-libs -Arch x86_64`，再执行 `doctor`。另一个架构的缓存可用 `-Arch aarch64` 获取。离线目录可通过 `./host/gpupv-host.ps1 doctor --wsl-lib-dir D:\runtime\x64` 指定，打包和推送支持同一参数。工具按已有 WSL 目录、显式目录、本地已校验缓存的顺序查找运行库。只有 fetch 命令联网。

三个 DirectX Linux 运行库属于微软专有二进制，厂商驱动受各自许可约束。源码包仅包含下载逻辑与固定摘要。生成的设备 tar、ISO 和缓存仅供有相应许可的本地部署，勿随开源源码发布。缓存以固定提交、逐文件 SHA-256 与 ELF 架构校验，摘要证明与选定社区镜像一致。版本和路径见 [校验清单](../host/wsl-runtime.json) 与[运行库来源](https://github.com/SherryPlatform/Microsoft.DirectX.Linux.Binaries/tree/a8ff069a0325c16d9ae7329382a929fbfc5fdfe9)。

在未手动挂载的来宾内，可用这一行完成挂载与离线安装。已有受信任 MOK 的来宾可以直接执行。首次生成 MOK 时按安装器提示确认后重新执行。

```sh
sudo mkdir -p /mnt/gpupv && { mountpoint -q /mnt/gpupv || sudo mount -o ro "$(sudo blkid -L GPUPV)" /mnt/gpupv; } && sudo sh /mnt/gpupv/guest/setup
```

微软 WSL 3.0.5 x64 MSI 的 File 表含有三个 DirectX Linux 运行库。测试只读提取其内嵌的 cab3.cab 并核对三个 ELF，逐文件 SHA-256 均与本项目固定的社区镜像一致。详见[官方包来源与 SHA-256](../artifacts/reports/2026-11-24/msi-file-table.json)和[逐文件对照](../artifacts/reports/2026-11-24/official-runtime-compare.json)。

Ubuntu 云镜像还需要与运行内核匹配的虚拟 PCI 控制器。若 `modinfo pci_hyperv` 提示模块缺失，请从对应 Ubuntu 仓库或离线介质安装 `linux-modules-extra-$(uname -r)` 并加载 `pci_hyperv`。单有 `/dev/dxg` 无法判断虚拟 PCI 设备是否已连接。

Arch 官方云镜像的默认启动器为 GRUB。使用 MOK 时，需要通过 shim 引导可信的内核，并让内核从 MokListRT 加载证书。本轮在测试磁盘上保留了原启动器，用 Arch 自带的内核与 initramfs 生成并签署 UKI，在 Hyper-V 为该测试机启用 Microsoft UEFI CA 模板。实际启动日志记录了 Secure Boot 和 GPU-PV 证书。已有受信任启动链的用户可直接使用自己的 MOK。[Arch 签名启动日志](../artifacts/reports/2026-11-24/arch-kernel-trust.txt) · [Arch UKI 文档](https://wiki.archlinux.org/title/Unified_kernel_image)

openSUSE Leap 上需同时核对内核头文件和第三方模块策略。本次云镜像自带的内核为 6.4.0-150600.23.146-default，启用的软件源提供 6.4.0-150600.23.103-default 和匹配的 devel 包。测试在来宾内并行安装并引导这组发行版内核。若 modprobe 报告 module is unsupported，请由来宾管理员按照 SUSE 文档决定是否允许外部模块。测试工具只在一次性 Leap 来宾中保存原设置，启用该选项，并在卸载后恢复。[SUSE 第三方内核模块说明](https://documentation.suse.com/sles/15-SP6/html/SLES-all/cha-adm-support.html)
