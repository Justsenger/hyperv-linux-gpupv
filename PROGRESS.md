# 进度记录

第一阶段计算版生成独立 x86_64 / aarch64 部署包。在 Windows Dev Kit 2023 上，ARM64 实测覆盖 Adreno 计算、Secure Boot 签名重启、非 systemd 来宾和卸载重启。扩测按内核分别记录计算结果、内核返回码及环境限制。[ARM64 扩测矩阵](artifacts/reports/arm64-expanded/results.md) · [首轮 ARM64 实测](artifacts/reports/arm64-devkit-2023/results.md) · [此前计算版实测](artifacts/reports/phase1/results.md)

## 此前单卡视频版

冻结介质在八个发行版上完成 16 组逐卡验收。RTX 2060 的 nvidia-smi、CUDA 数值校验和 H.264 NVENC/CUVID 分别通过 8/8、8/8、8/8。Iris Xe 的 D3D12 Compute 通过 8/8，H.264 硬编与 VP9 硬解通过 8/8。普通用户重启访问、重复安装和卸载重启清理通过 16/16。Secure Boot 签名加载通过 16/16，模块验证告警共 0 条。16 组仍记录 dxgkrnl ioctl 错误，严格全项通过 0/16。 [逐卡验收和原始证据](artifacts/reports/2026-11-24/final-matrix.md)

2026-11-24 候选版在新版 Intel 32.0.101.6876 和 NVIDIA 32.0.16.1742 上进行无桌面回归。八个基座的 RTX 2060 CUDA、NVENC 和 CUVID 均已取得正向证据，原生构建与 DKMS 签名已在受信任启动链上实测。Intel H.264 硬件往返和严格内核日志仍有失败。[本轮矩阵](artifacts/reports/2026-11-24/matrix.md) · [双卡 ioctl 与 VMBus 实测](artifacts/reports/2026-11-24/driver-calls.md) · [候选介质之间的源码差异](artifacts/reports/2026-11-24/rc1-to-rc2-files.json)

2026-11-23 开发预览。在未安装 WSL 的宿主生成了两张显卡的 x64 部署包和 UDF ISO。Debian 13 的 RTX 2060 已通过普通用户 CUDA 和编解码测试；严格内核日志检查检测到模块签名告警。各项目证据见 [兼容性记录](COMPATIBILITY.md)。

|阶段|已取得的证据|
|---|---|
|0 宿主盘点|Windows 11 Pro Build 26200，Intel Iris Xe 与 GeForce RTX 2060 均列为可分区设备。已验证测试 VM 的创建、启动、检查点和还原。|
|0.5 上游调研|记录 8 个参考仓库的提交和许可边界，保留内核源码及配套 UAPI。|
|1 双端工具|完成宿主选择与导出、单文件 SSH 推送、UDF 制作、来宾体检、安装、验收和卸载代码。真实宿主验证出 18 个 NVIDIA INF 运行库文件映射。|
|2 编译|Phase 2 源码快照的 22 个容器目标中 20 个生成可审计模块。另在真实 Debian 13 VM 通过运行内核的 Kbuild 和 DKMS 编译。|
|3 真机|7 个来宾基座、14 次逐卡 VMBus 枚举取得证据；Debian 12 验证不同 boot ID。宿主缺库、Secure Boot、musl、移除当前内核 headers 及只读挂载均被拦截。|
|4 交付|提供源码工具包、兼容性表、完整日志索引及清理清单。当前验证状态见逐次试验索引。|

x64 与 aarch64 均已完成显式下载与校验，x64 已导出两张卡的 tar 与 UDF ISO。Debian 13 和 Ubuntu 22.04、24.04 已在普通用户会话取得 RTX 2060 真实计算及 15 帧硬编解码证据。Ubuntu 24.04 的运行日志暴露了变长栅栏字段的 FORTIFY 告警，已修正结构并重建介质。严格内核日志结果及后续发行版在[逐次试验索引](artifacts/reports/e2e-index.md)中记录。

Fedora 44 原生 SELinux 拒绝 systemd-modules-load 从 /opt 下标记为 usr_t 的模块加载。已修复原生模块发布路径，使用发行版模块树中的普通文件、恢复策略标签并通过清单摘要核对卸载归属。未改动 SELinux 策略。验收保留修复前的 AVC 原文和修复后的重启日志。

### 本次交付版本的实测结果

模块源码 SHA-256 为 `47bdacc5597ebe41022076e2d6402a70397c2a36ee4ab2f2975ae2d514e79215`。容器构建 18/22 项通过，逐项记录见[构建复核](artifacts/reports/release-compilation.json)。

完整结果见 [COMPATIBILITY.md](COMPATIBILITY.md)。
