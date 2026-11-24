# phase1-local.2 本地计算验收

Windows x64 Hyper-V，宿主驱动为 NVIDIA 32.0.16.1742 和 Intel 32.0.101.6876。两张卡同时分配给 Debian 12 Gen2 来宾，运行内核为 6.1.0-56-amd64。普通用户 uid 1000 属于 video 组。所有本轮数值测试均使用计算 API。[驱动清单](host-drivers.txt) · [来宾基线](guest-before.txt)

## 包含的模块

| 架构 | 发行版和内核 | 构建来源 | 交付验证 |
| --- | --- | --- | --- |
| x86_64 | Debian 12，6.1.0-56-amd64 | 在本机 Hyper-V 来宾内使用原生 Debian 12 Docker 容器构建 | 模块加载，双卡硬件数值测试 |
| aarch64 | Debian 12，6.1.0-56-arm64 | x86_64 Debian 来宾、对应版本的官方 arm64 头文件与 AArch64 交叉工具链 | 模块 ELF、摘要、vermagic、srcversion 校验。用 QEMU 用户态的 ARM64 glibc 加载器解析探针和三份运行库的依赖 |

本轮没有 ARM64 Hyper-V 物理宿主。ARM64 内核加载、GPU-PV、Windows ARM64 厂商 UMD 提取以及 ARM64 原生 CI 均待对应环境验证。两个本地探针的最高 glibc 符号版本均为 2.17。[x64 容器模块记录](container-debian12-module.json) · [ARM64 编译记录](aarch64-module.json) · [探针 ABI](probe-abi.txt) · [ARM64 加载器记录](arm64-loader.txt)

## 双卡工作负载

| 项目 | 本机实测 |
| --- | --- |
| 内核通道 | 普通用户打开 /dev/dxg 读写，真实重启前后 boot ID 不同 |
| D3D12 Compute | DXCore 枚举两张硬件卡，Intel 8086:9a49 和 NVIDIA 10de:1f15 各有 64/64 项回读正确 |
| NVIDIA | RTX 2060，617.42，6144 MiB。三个 CUDA 结果为 38、136、892 |
| Intel OpenCL | 安装 Debian 的 intel-opencl-icd 和 ocl-icd-libopencl1 后，Iris Xe 32/32 项正确，最后一项为 220 |
| Secure Boot | 本地生成来宾 MOK，在 shim 确认登记。无 GCC、make 和运行内核头文件时，独立 CMS 签名后成功加载。签名者 GPU-PV module signing，模块 taint 为 O，已测签名启动中 module verification failed 为 0 |
| 重复安装及卸载 | 从 UDF 重复执行 install 成功。卸载后模块、设备和安装目录消失，随后重启核查 |

关闭 Secure Boot 时安装器跳过签名；签名告警计数只取开启 Secure Boot 且已登记 MOK 的测试启动。

[正式本地包安装原文](final-install.txt) · [重启后的数值及卸载](final-signed-reboot.txt) · [新机登记引导](enrollment.txt)

## SSH 一键部署

以最终 x64 ZIP 和两张实际显卡为输入，宿主 gpupv-host push 通过固定主机密钥的 SSH 将部署载荷送入已卸载干净的测试 VM。关闭 Secure Boot，未安装 GCC、make 或当前内核头文件。安装后自动运行普通用户设备体检，另行执行完整双卡 D3D12、CUDA、OpenCL 数值验证，确认模块没有附加签名，随后卸载并重启。[宿主推送及工作负载](final-ssh-install.txt) · [普通用户计算窗口](final-ssh/compute-dmesg.txt) · [卸载后重启](final-clean.txt)

## 纯计算窗口内的内核日志

每次负载前在 /dev/kmsg 写入唯一标志，仅统计标志之后的日志。未装 OpenCL ICD 的三次测试记录到 0 条 -75。装入 ICD 后，开启 Secure Boot、重启后的整组负载都复现两条 dxgkio_reserve_gpu_va: Ioctl failed: -75。分别运行 NVML、D3D12、CUDA 和 OpenCL 时，只有 Intel OpenCL 窗口复现这两条。OpenCL 仍完整读回 32 个正确的元素。另见查询接口的 -2/-22 与 escape 的 -22；本轮没有过滤错误或更改内核返回值。现有证据可以定位到对应的 Linux 工作负载及 ioctl，尚无法确定 Windows 驱动内部原因。

[按调用和错误码计数](isolated-ioctl.json) · [独立 NVML](compute-isolated/nvml.dmesg) · [独立 D3D12](compute-isolated/d3d12.dmesg) · [独立 CUDA](compute-isolated/cuda.dmesg) · [独立 OpenCL](compute-isolated/opencl.dmesg) · [OpenCL 回读值](compute-isolated/opencl.stdout) · [早期单卡调用分析](../2026-11-24/driver-calls.md)

## 自动化与构建覆盖

- 两个部署 ZIP 均通过内容、CRC、三份固定运行库 SHA-256、探针与模块 ELF 校验。向两个架构分别提供另一包均被拒绝。本机宿主 doctor 实际接受 x64、拒绝 ARM64。[包测试](bundle-verification.txt) · [宿主读取的最终 manifest](host-verified-manifest.json)
- 多卡实例、同型号歧义、未知或重复 GPU、同名同摘要和不同摘要别名均有正反例。[PowerShell 测试](host-contract-tests.txt)
- 第一份介质在独立的 Debian 12 特权容器中通过无编译工具预编译模块实装、二次安装和卸载。容器共享测试 VM 的内核和 udev，并使用该机登记过的测试密钥。精简容器没有发行版 modules.order 等索引，depmod 提示保留在原始日志。最终介质的无头文件安装在 VM 本身复验。[容器实装](no-tools-container.txt)
- OpenSSL 验证了独立签名器和发行版内核 sign-file 产生的两个 CMS 签名，校验了完整模块内容及尾标格式。[签名对照](signature-reference.txt)
- 本地生成 126 个原生构建任务，x86_64 为 67 个，aarch64 为 59 个。逐项核对 49 个独立镜像标签在 registry 的平台描述；该检查只验证容器清单。已校验两份 TrueNAS 定制头文件 URL 及 SHA-256。完整发行版矩阵等远端建立后执行，本地实际入包的全部内核列于上表。[容器镜像记录](registry-images.json) · [定制头文件记录](custom-headers.json) · [workflow 静态检查](workflow-check.txt)

旧版逐卡视频回归留在单独的历史目录。当前发布范围不含视频、OpenGL 或 Vulkan 验收。[历史矩阵](../2026-11-24/final-matrix.md)

## 本地交付与清理

公开部署包与纯源码 ZIP 在 dist/phase1，按该目录的 SHA256SUMS 校验。已测双卡私有 UDF 单独保存在 dist/local-media，共 6,137,511,936 字节，SHA-256 为 43f78e37c4f2e702d4a2a6c4c1391933e2e754f86b3218f9aef61b9ad721fae9。该文件包含本机显卡 UMD。测试 VM、临时磁盘、SSH 私钥及暂存目录均已清理。[清理记录](vm-cleanup.txt)
