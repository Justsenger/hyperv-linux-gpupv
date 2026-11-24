# 第一阶段计算版兼容性

## GitHub Actions 成品验收

原生 x86_64 和 aarch64 runner 分别生成包含 166 和 118 个不同内核 release 的部署包。两包均通过三份微软运行库的固定摘要、模块 ELF、manifest 和跨架构拒绝检查。Debian 12 x86_64 是本次硬件验收环境。ARM64 已完成原生编译和成品检查，尚无 ARM64 Hyper-V GPU 运行证据。[发行版和内核逐项记录](artifacts/reports/actions-native-matrix.md) · [成品打包记录](https://github.com/Justsenger/hyperv-linux-gpupv/actions/runs/45390694286)

本机将试构建成品与 RTX 2060、Iris Xe 宿主驱动合并为 UDF 光盘。全新 Debian 12 来宾在 6.1.0-56-amd64 上无需 gcc、make 或内核头。关闭 Secure Boot 时重复安装及重启后读写 /dev/dxg 均通过。开启 Secure Boot 后，首次安装提示 MOK 导入；录入公钥并真实重启后以受信任签名加载，启动日志中模块签名验证警告为零。

普通用户在两种启动模式下均获得两张硬件适配器，D3D12 各回读 64/64，CUDA 三组数值均正确。工作负载区间的 dmesg 未出现 -75，保留了 escape -22、query_adapter_info -2/-22 等诊断。该结果不计为内核零报错。[关闭 Secure Boot 的数值输出](artifacts/reports/ci-bundle-ca173d3/accept-off/compute.txt) · [安全启动与数值输出](artifacts/reports/ci-bundle-ca173d3/signed-after-reboot.txt) · [内核日志](artifacts/reports/ci-bundle-ca173d3/accept-signed/compute-dmesg.txt)

## 较早的 phase1-local.2 本地试验

| 架构 | 本地包内的全部预编译内核 | 验证环境 |
| --- | --- | --- |
| x86_64 | Debian 12，6.1.0-56-amd64 | Debian 原生编译，Hyper-V 双卡 UDF 与 SSH 部署；签名启动、重启和普通用户数值验证 |
| aarch64 | Debian 12，6.1.0-56-arm64 | 真实 Debian ARM64 头文件交叉编译，ELF 与包内容校验。尚待 ARM64 Hyper-V 实机验证 |

[本轮测试结果与限制](artifacts/reports/phase1/results.md)。精确内核未命中时走源码编译。Void glibc、Artix、Devuan、Slackware 等非 systemd 系统使用 udev PCI 事件触发加载，需有可工作的 udev 守护进程。此路径尚无独立启动实测。Alpine/musl、不可变根和未提供所需页固定接口的内核不适用。每个 CI 目标的声明、容器与架构可查看 [targets/matrix.json](targets/matrix.json)。衍生版自有内核需要自己的头文件包。

## 历史逐发行版结果

以下记录对应先前介质与当时的驱动，保留其原始判定。

# 兼容性与证据

### 2026-11-24 新驱动回归

冻结介质在八个发行版上完成 16 组逐卡验收。RTX 2060 的 nvidia-smi、CUDA 数值校验和 H.264 NVENC/CUVID 分别通过 8/8、8/8、8/8。Iris Xe 的 D3D12 Compute 通过 8/8，H.264 硬编与 VP9 硬解通过 8/8。普通用户重启访问、重复安装和卸载重启清理通过 16/16。Secure Boot 签名加载通过 16/16，模块验证告警共 0 条。16 组仍记录 dxgkrnl ioctl 错误，严格全项通过 0/16。 [逐卡验收和原始证据](artifacts/reports/2026-11-24/final-matrix.md)

冻结的本地部署包和可选 VA 用户态环境均使用 SHA-256 清单。下表索引按新介质的普通用户测试、签名、卸载和 dmesg 原始记录分别判定，调参和先导结果保留在当日完整索引中。[最终候选介质逐组合结果](artifacts/reports/2026-11-24/final-matrix.md) · [全部对照与重试](artifacts/reports/2026-11-24/matrix.md) · [签名告警与 ioctl 错误计数](artifacts/reports/2026-11-24/kernel-diagnostics.json)

本轮宿主为 Windows Build 26200，RTX 2060 驱动为 32.0.16.1742（来宾报告 617.42），Iris Xe 驱动为 32.0.101.6876。按单卡绑定的真实 Hyper-V 来宾分别检查内核通道、计算、RTX 的 H.264 编解码，以及 Iris Xe 的 H.264 编码与 VP9 解码。本轮不评估桌面渲染。严格日志门槛尚未达到，当前交付等级为候选版。[宿主体检](artifacts/reports/2026-11-24/host-doctor.json) · [Intel 主包、注册表与关联 INF](artifacts/reports/2026-11-24/intel-host.json)

**RTX 2060 的硬件功能已通过 8/8。** 八个基座均获得显存和驱动信息、三个正确的 CUDA 测试值及 H.264 NVENC/CUVID 的 15 帧回读。Arch 7.3.4-arch1-2 使用本机测试 MOK 签署的 UKI 引导。普通用户工作负载、重复安装、卸载后重启和测试机回收均已完成。Arch 的严格失败项为工作负载前后的内核诊断。[本轮逐次记录](artifacts/reports/2026-11-24/matrix.md) · [Arch 工作负载](artifacts/reports/gpupv-test-1ce51a8e569446cd989c198aa68322f7-4f07d11e/workload.txt) · [Arch 严格结果](artifacts/reports/gpupv-test-1ce51a8e569446cd989c198aa68322f7-4f07d11e/result.json)

**Iris Xe 的 DXCore 枚举与 D3D12 Compute 已通过 8/8。** Arch 原生 Mesa 26.3.1、Leap 隔离 Mesa 25.2.8 都完成了 VP9 硬件解码。探针要求 VA 硬件帧，经 hwdownload 回读，与同一输入的软件参考解码逐帧匹配 15/15。独立 HEVC 编码在这两台来宾均未取得有效码流。Arch 原生 H.264 报告 15 帧已编码、14 包已封装，但合计 0 字节。[Arch 独立 VP9 与 HEVC 测试](artifacts/reports/gpupv-test-2729c6f5348a4774a22d5de227279342-d8ac5364/intel-video-profiles.txt) · [Arch H.264 码流](artifacts/reports/gpupv-test-2729c6f5348a4774a22d5de227279342-d8ac5364/workload.txt) · [Leap 独立视频测试](artifacts/reports/gpupv-test-497b799c22614660aa9218dd8346ce52-aeb48afd/isolated-intel-va.txt)

**Intel 正向视频配置。** 在 Fedora 44 与 Arch 的独立 Ubuntu Mesa 25.2.8 环境中，H.264 Constrained Baseline、CBR 1 Mbit/s、GOP 1、无 B 帧、异步深度 1 均产生了 153,928 字节的有效码流，独立解码得到 15 帧。VP9 硬解的 15 帧逐帧匹配参考解码。常规 H.264 High/CQP 编码和同编码器的 HEVC 路径仍有失败。当前 Intel 主验收分别验证 H.264 硬编与 VP9 硬解。[Fedora 参数、码流与帧校验](artifacts/reports/gpupv-test-3e07478a6eec4522937eb67fdc207ee2-756107b8/isolated-intel-va.txt)

**Rocky 9 的 Intel 视频需要额外的 DRM 模块。** 官方运行内核 5.14.0-741.22.1.el9_9.x86_64 关闭了 CONFIG_DRM_VGEM。单独提供同批 Mesa 并加载发行版 VKMS 后，Hyper-V framebuffer 和 VKMS 节点都在 vaInitialize 返回 2。在同一台已开启 Secure Boot 的来宾，用官方签名的同版本内核 SRPM 构建原样 VGEM，以已录入的 MOK 签名并临时加载，出现 /dev/dri/renderD128。其余配置保持一致，普通用户运行 gpupv-guest verify 得到 153,928 字节的 H.264 硬编输出和 15/15 帧匹配的 VP9 硬解结果。该补充模块只在本次启动加载，随后显式卸载。标准安装器不安装或持久化 VGEM 源外模块。[原始配置及 VKMS](artifacts/reports/gpupv-test-cad5cabe22f94eb989e1f00473f36124-8d313c9f/rocky-drm-modules.txt) · [VKMS 对照](artifacts/reports/gpupv-test-cad5cabe22f94eb989e1f00473f36124-8d313c9f/isolated-intel-va.txt) · [编译、签名和加载](artifacts/reports/gpupv-test-cad5cabe22f94eb989e1f00473f36124-8d313c9f/rocky-signed-vgem.txt) · [VGEM 硬件负载](artifacts/reports/gpupv-test-cad5cabe22f94eb989e1f00473f36124-8d313c9f/isolated-intel-vgem.txt) · [Rocky 官方源 RPM](https://dl.rockylinux.org/pub/rocky/9/BaseOS/source/tree/Packages/k/kernel-5.14.0-741.22.1.el9_9.src.rpm)

Ubuntu 22.04 原生 Mesa 23.2.1 还取得 H.264 同编码格式往返的正向结果。普通用户通过 /dev/dri/card1 在 Iris Xe 上编码 H.264 High 裸码流，随后强制 VA 硬件解码，将 15 帧下载回读并记录每帧摘要。该次重启后的签名与卸载检查均完成，严格失败项为工作负载后的内核诊断。[完整 H.264 往返](artifacts/reports/gpupv-test-c75677bb0e924c6db5aa24dbb73d53ac-ffb6ebfd/workload.txt) · [严格检查](artifacts/reports/gpupv-test-c75677bb0e924c6db5aa24dbb73d53ac-ffb6ebfd/result.json)

openSUSE Leap 15.6 在 Secure Boot 开启、MOK 已录入的情况下，重启后普通用户通过了 RTX 2060 CUDA 三项数值校验和 NVENC/CUVID 15 帧往返校验。重复安装、卸载重启和 SUSE 第三方模块策略恢复均有记录。GPU 调用仍触发内核诊断。[签名状态](artifacts/reports/gpupv-test-eb87e66daecc42668e5f824a52af7fd8-b3def52c/module-trust-after-boot.txt) · [工作负载](artifacts/reports/gpupv-test-eb87e66daecc42668e5f824a52af7fd8-b3def52c/workload.txt) · [严格结果](artifacts/reports/gpupv-test-eb87e66daecc42668e5f824a52af7fd8-b3def52c/result.json)

宿主 Iris Xe 为 32.0.101.6876。Debian 13 的 6.12.118+deb13-amd64 在 Secure Boot 开启并录入 MOK 后加载签名模块，普通用户重启后可打开 dxg，DXCore 枚举到一个硬件适配器 8086:9a49。D3D12 Compute 使用 DXIL cs_6_0，64 项 GPU 回读均正确。该次启动仍有 is_feature_enabled 和 query_adapter_info 返回错误。[重启与计算日志](artifacts/reports/2026-11-24/pilot-secure-compute-postboot.txt)

Debian 的 Mesa 25.0.7 在 vgem 节点上通过 D3D12 查询到 Intel H.264 编码与解码入口。实测硬编码等待 77 秒仍为零帧，独立 H.264 硬解码在 Intel 用户态库 libigd12dxva64.so 内发生段错误。此组合的视频未通过。[编码日志](artifacts/reports/2026-11-24/pilot-va-h264.txt) · [解码日志](artifacts/reports/2026-11-24/pilot-va-decode.txt) · [等待点和内核日志](artifacts/reports/2026-11-24/pilot-video-stall.txt)

Fedora 44 通过 D3D12 Compute 64/64 与 Intel OpenCL 32/32 校验。官方 Mesa 26.2.7 识别出 D3D12 Intel Iris Xe，报告 VP9 与 AV1 解码能力，H.264 编码和解码入口均未出现。Leap 15.6 通过 D3D12 Compute 64/64。单独为这台来宾提供 Ubuntu 官方 Mesa 25.2.8、FFmpeg 和 vainfo 后，H.264 硬编码进入 Intel VA 设备，但 60 秒内未完成，被限时器终止。[Fedora 工作负载](artifacts/reports/gpupv-test-da7ac386ff754cebb650e8c89b25f387-0ec5daaf/workload.txt) · [Leap 隔离环境与编码日志](artifacts/reports/gpupv-test-91eb68325f1a4467ba98ec1a6543d604-58c89ab6/isolated-intel-va.txt)

Debian 13 同一台来宾切换到 RTX 2060 后，在 Secure Boot 重启后得到 6144 MiB 显存信息、三个正确的 CUDA 结果与 15 帧 NVENC/CUVID 回读。Debian 12 已观察到相同的功能验收和重启卸载通过。严格日志检查仍有错误。[双卡调用与事务](artifacts/reports/2026-11-24/driver-calls.md) · [Debian 12 回归](artifacts/reports/2026-11-24/deb12-rtx-run.txt)

### 2026-11-23 历史矩阵

本轮在 Windows 11 Pro Build 26200 上，用 RTX 2060 和 Iris Xe 分别测试了 Ubuntu 22.04、Ubuntu 24.04、Debian 12、Debian 13、Fedora 44、Rocky 9、Arch 和 openSUSE Leap 15.6。RTX 2060 在 8 个基座均完成普通用户 CUDA 数值校验及 15 帧 NVENC/CUVID 硬件编解码。Iris Xe 尚无基座取得硬件渲染通过结果。严格全项通过 0/16。完整日志见[逐组合真机记录](artifacts/reports/e2e-index.md)。

8 个基座均使用独立的真实 Hyper-V 来宾。Fedora、Rocky 和 Leap 的 RTX 编解码使用来自 Ubuntu 24.04 的隔离 FFmpeg，与来宾打包流程分开。Leap 使用发行版内核 6.4.0-150600.23.103-default，基于 SUSE 的配置明确允许第三方模块，卸载后恢复原设置。NVIDIA 内核日志中的模块签名与 GPU ioctl 诊断保留在每次试验记录内。

截至 2026-11-23，Phase 2 源码快照（摘要见每份构建日志）的 22 个容器目标中有 20 个实际生成了 dxgkrnl.ko。每个通过项均核对了模块名、vermagic、模块 SHA-256、源码摘要和最终退出码。

|Hyper-V 真机实测全通过|仅编译矩阵通过|明确不支持及拦截测试结果|
|---|---|---|
|0 项。x64 运行库已校验，完整工作负载验收见下文。|[alma-8 · 4.18.0-553.187.1.el8_10.x86_64](artifacts/reports/compile-matrix/final/alma-8.log)|[历史保护测试中没有可用的运行库，tar 与 ISO 导出均在生成文件前退出](artifacts/reports/host-pack-guards.txt)|
||[alma-9 · 5.14.0-741.24.1.el9_9.x86_64](artifacts/reports/compile-matrix/final/alma-9.log)|[x64 宿主收到 aarch64 目标参数后退出](artifacts/reports/host-arch-mismatch.txt)|
||[anolis-23 · 6.6.102-8.0.2.an23.x86_64](artifacts/reports/compile-matrix/final/anolis-23.log)|[Ubuntu 24.04 启用 Secure Boot，安装退出](artifacts/reports/final-secure-boot-guard.txt)|
||[arch-lts · 6.18.64-1-lts](artifacts/reports/compile-matrix/final/arch-lts.log)|[Alpine 3.23.4 使用 musl，安装退出](artifacts/reports/final-musl-guard.txt)|
||[arch · 7.3.5-arch1-1](artifacts/reports/compile-matrix/final/arch.log)|[Debian 13 移除精确版本 headers 后安装退出](artifacts/reports/removed-headers.txt)|
||[debian-11-archive · 5.10.0-46-amd64](artifacts/reports/compile-matrix/final/debian-11-archive.log)|[Debian 13 私有挂载命名空间内将根重挂为只读，安装退出](artifacts/reports/debian-readonly.txt)|
||[debian-11-base · 5.10.0-32-amd64](artifacts/reports/compile-matrix/final/debian-11-base.log)|[Debian 11 实时安全镜像缺包，HTTP 404](artifacts/reports/compile-matrix/final/debian-11.log)|
||[debian-12 · 6.1.0-56-amd64](artifacts/reports/compile-matrix/final/debian-12.log)|[Ubuntu 20.04 GA 5.4 缺少所需的页固定接口](artifacts/reports/compile-matrix/final/ubuntu-20.04.log)|
||[debian-13 · 6.12.118+deb13-amd64](artifacts/reports/compile-matrix/final/debian-13.log)||
||[fedora-43 · 7.3.4-100.fc43.x86_64](artifacts/reports/compile-matrix/final/fedora-43.log)||
||[fedora-44 · 7.3.4-200.fc44.x86_64](artifacts/reports/compile-matrix/final/fedora-44.log)||
||[leap · 6.4.0-150600.23.103-default](artifacts/reports/compile-matrix/final/leap.log)||
||[openeuler · 6.6.0-145.0.13.139.oe2403.x86_64](artifacts/reports/compile-matrix/final/openeuler.log)||
||[rocky-8 · 4.18.0-553.187.1.el8_10.x86_64](artifacts/reports/compile-matrix/final/rocky-8.log)||
||[rocky-9 · 5.14.0-741.24.1.el9_9.x86_64](artifacts/reports/compile-matrix/final/rocky-9.log)||
||[tumbleweed · 7.3.5-1-default](artifacts/reports/compile-matrix/final/tumbleweed.log)||
||[ubuntu-20.04-hwe · 5.15.0-139-generic](artifacts/reports/compile-matrix/final/ubuntu-20.04-hwe.log)||
||[ubuntu-22.04 · 5.15.0-204-generic](artifacts/reports/compile-matrix/final/ubuntu-22.04.log)||
||[ubuntu-24.04 · 6.8.0-151-generic](artifacts/reports/compile-matrix/final/ubuntu-24.04.log)||
||[ubuntu-26.10 · 7.3.0-11-generic](artifacts/reports/compile-matrix/final/ubuntu-26.10.log)||
||[Debian 13 VM · 6.12.117+deb13-amd64 · Kbuild](artifacts/reports/compile-matrix/debian-13-native-final.log)||
||[同一 Debian 13 VM · DKMS build](artifacts/reports/compile-matrix/debian-13-dkms-final.log)||

Windows 11 专业版 Build 26200 上，已在 7 个来宾基座记录了 14 项单卡 VMBus 枚举。后续使用实际离线载荷的重启、工作负载与卸载结果见[逐次验收索引](artifacts/reports/e2e-index.md)。[逐卡日志](artifacts/reports/transport-summary.md)

实时源、基础仓库、历史快照、GA、HWE 和 LTS 各按各自头文件统计。跨内核使用需重新编译。桌面 Mesa 隔离运行时未打包。

### Debian 13 真机工作负载（Windows 11 Pro 26200，Linux 6.12.117+deb13-amd64）

|项目|GeForce RTX 2060|Intel Iris Xe|
|---|---|---|
|重启后普通用户访问|uid 1000，video 组，可读写字符设备|uid 1000，video 组，可读写字符设备|
|计算与图形|6144 MiB，KMD 617.42，CUDA 三组结果为 38、136、892，H.264 NVENC→CUVID 15 帧回读|DXCore 创建工厂与 D3D12 图形列表均成功，适配器数为 0。系统 Vulkan 仅列出 llvmpipe，GLX 创建上下文失败|
|安装与卸载|重复安装成功，卸载后重启检查通过|重复安装成功，卸载后重启检查通过|
|严格内核日志|启动时内核报告外部模块签名验证失败|启动时内核报告外部模块签名验证失败|

[NVIDIA 工作负载原始输出](artifacts/reports/gpupv-test-586ad69530d74ef195559270615d3f6c-a54d020f/independent-nvidia.txt) · [NVIDIA 卸载后重启](artifacts/reports/gpupv-test-586ad69530d74ef195559270615d3f6c-a54d020f/uninstall-after-reboot.txt) · [Intel API 输出](artifacts/reports/gpupv-test-586ad69530d74ef195559270615d3f6c-cc6435f9/workload.txt) · [Intel DXCore 探针](artifacts/reports/debian13-intel-dxcore.txt)

本机 Intel 驱动 27.20.100.8935 的设备包未提供 Linux 图形用户态驱动映射。Intel 的 EFLOW GPU-PV 指南列出的 WSL GPU 驱动最低版本为 30.0.100.9955。独立安装来宾 Mesa 可以改变 API 支持范围，但本次在 Mesa 之下直接调用 DXCore 已经返回零个 D3D12 图形适配器。参见 [Intel 指南 §2.2](https://cdrdv2-public.intel.com/648435/648435_1.5_EFLOW-AI-Inference-with-GPU-User-Guide.pdf)。

### Fedora 44 真机复测

在 SELinux enforcing 的 Fedora Cloud 44、内核 6.19.10-300.fc44.x86_64 上，初次 RTX 2060 试验中 systemd 被拒绝从 /opt 加载模块。修正安装位置后，Iris Xe 来宾中的模块位于内核 updates 目录，文件类型为 modules_object_t。普通用户在实际重启后可读写 /dev/dxg。发行版提供 Mesa Dozen，限定只用其 ICD 时，Vulkan 枚举返回 ERROR_INITIALIZATION_FAILED。默认枚举得到 llvmpipe，Iris Xe 图形验收失败。

[模块位置与 SELinux 类型](artifacts/reports/gpupv-test-180f1f5e1d7846988fce9978d395ca4a-17b599e8/installed-module.txt) · [重启后设备权限](artifacts/reports/gpupv-test-180f1f5e1d7846988fce9978d395ca4a-17b599e8/access.txt) · [单独启用 Dozen 的原始输出](artifacts/reports/gpupv-test-180f1f5e1d7846988fce9978d395ca4a-17b599e8/dozen-isolated.txt)

### 本次交付版本的实测结果

模块源码 SHA-256 为 `47bdacc5597ebe41022076e2d6402a70397c2a36ee4ab2f2975ae2d514e79215`。容器构建 18/22 项通过，逐项记录见[构建复核](artifacts/reports/release-compilation.json)。

|发行版与显卡|实际工作负载|安装与卸载|严格验收|
|---|---|---|---|
|arch / Intel|硬件工作负载未通过|重启权限通过 / 重复安装通过 / 卸载重启通过|未通过|
|arch / NVIDIA|CUDA 数值通过，NVENC/CUVID 15 帧|重启权限通过 / 重复安装通过 / 卸载重启通过|未通过|
|debian-12 / Intel|仅见软件设备或硬件上下文失败|重启权限通过 / 重复安装通过 / 卸载重启通过|未通过|
|debian-12 / NVIDIA|CUDA 数值通过，NVENC/CUVID 15 帧|重启权限通过 / 重复安装通过 / 卸载重启通过|未通过|
|debian-13 / Intel|仅见软件设备或硬件上下文失败|重启权限通过 / 重复安装通过 / 卸载重启通过|未通过|
|debian-13 / NVIDIA|CUDA 数值通过，NVENC/CUVID 15 帧|重启权限通过 / 重复安装通过 / 卸载重启通过|未通过|
|fedora-44 / Intel|仅见软件设备或硬件上下文失败|重启权限通过 / 重复安装通过 / 卸载重启通过|未通过|
|fedora-44 / NVIDIA|CUDA 数值通过，NVENC/CUVID 15 帧|重启权限通过 / 重复安装通过 / 卸载重启通过|未通过|
|leap-15.6 / Intel|硬件工作负载未通过|重启权限通过 / 重复安装通过 / 卸载重启通过|未通过|
|leap-15.6 / NVIDIA|CUDA 数值通过，NVENC/CUVID 15 帧|重启权限通过 / 重复安装通过 / 卸载重启通过|未通过|
|rocky-9 / Intel|仅见软件设备或硬件上下文失败|重启权限通过 / 重复安装通过 / 卸载重启通过|未通过|
|rocky-9 / NVIDIA|CUDA 数值通过，NVENC/CUVID 15 帧|重启权限通过 / 重复安装通过 / 卸载重启通过|未通过|
|ubuntu-22.04 / Intel|硬件工作负载未通过|重启权限通过 / 重复安装通过 / 卸载重启通过|未通过|
|ubuntu-22.04 / NVIDIA|CUDA 数值通过，NVENC/CUVID 15 帧|重启权限通过 / 重复安装通过 / 卸载重启通过|未通过|
|ubuntu-24.04 / Intel|仅见软件设备或硬件上下文失败|重启权限通过 / 重复安装通过 / 卸载重启通过|未通过|
|ubuntu-24.04 / NVIDIA|CUDA 数值通过，NVENC/CUVID 15 帧|重启权限通过 / 重复安装通过 / 卸载重启通过|未通过|

每次试验的启动记录、设备权限、计算与编解码输出、内核日志及失败重试均保存在[原始证据索引](artifacts/reports/e2e-index.md)。
