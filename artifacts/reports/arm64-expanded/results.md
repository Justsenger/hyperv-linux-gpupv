# ARM64 Hyper-V 算力回归

2026-11-25，Windows Dev Kit 2023，Windows build 29671，Qualcomm Adreno 8cx Gen 3，驱动 30.0.4122.4000。数值通过要求重启后普通用户在一个真实硬件适配器上完成 D3D12 Dispatch，并核对 64 个 GPU 回读结果。表中「清理」为卸载后再次重启的来宾检查。宿主删除测试 VM 另有记录。

矩阵共 59 个 aarch64 条目。实测未通过 6；签名计算及清理通过 27；范围或介质限制 5；矩阵排除 10；关闭安全启动后通过 11。同一条目额外尝试的不同内核或不同光盘不重复计数。

合并两轮实测，有独立计算窗口并通过计算与清理的条目 38 个，其中窗口内 ioctl 零错误 0 个。每个通过条目只计一个窗口，返回码合计 -22×152、-2×38。签名加载告警与计算窗口负返回码分别记录。带符号的历史跟踪将常见的四次 -22 定位到 feature 查询和 KMTUMDVERSION 0/1/2，一次 -2 定位到 DXCoreWSLAttributes。[首轮签名与错误定位](../arm64-devkit-2023/results.md)

| 矩阵条目 | 实际运行内核 | 安装方式 | Secure Boot | 验收 | 原始记录与限制 |
| --- | --- | --- | --- | --- | --- |
| ubuntu-20.04-hwe | 5.15.0-139-generic | 预编译，无工具/头文件 | 开 | 未完成验收，阶段 install | [状态](ubuntu-20.04-hwe/result.json) · [介质](ubuntu-20.04-hwe/image.json) · [清理](ubuntu-20.04-hwe/cleanup.txt) · [停点](ubuntu-20.04-hwe/install.txt)。 使用官方 5.15 HWE，已安装匹配的 modules-extra，modinfo 仍找不到 pci_hyperv。[传输层核对](ubuntu-20.04-hwe/transport-config.txt)。 |
| ubuntu-22.04-ga | 5.15.0-203-generic | 源码 | 开 | 未完成验收，阶段 install | [状态](ubuntu-22.04-ga/result.json) · [介质](ubuntu-22.04-ga/image.json) · [停点](ubuntu-22.04-ga/install.txt)。 5.15 GA 的 hv_pci 配置见首轮及本轮记录。 |
| ubuntu-22.04-hwe | 6.8.0-149-generic | 预编译，无工具/头文件 | 开 | 64/64，卸载重启通过 | [状态](ubuntu-22.04-hwe/result.json) · [介质](ubuntu-22.04-hwe/image.json) · [计算](ubuntu-22.04-hwe/workload.txt) · [签名](ubuntu-22.04-hwe/trust.txt) · [窗口 -22×4、-2×1](ubuntu-22.04-hwe/dmesg.txt) · [清理](ubuntu-22.04-hwe/cleanup.txt)。  |
| ubuntu-24.04-ga | 6.8.0-147-generic | 源码 | 开 | 64/64，卸载重启通过 | [状态](ubuntu-24.04-ga/result.json) · [介质](ubuntu-24.04-ga/image.json) · [计算](ubuntu-24.04-ga/workload.txt) · [签名](ubuntu-24.04-ga/trust.txt) · [窗口 -22×4、-2×1](ubuntu-24.04-ga/dmesg.txt) · [清理](ubuntu-24.04-ga/cleanup.txt)。  |
| ubuntu-24.04-hwe | 7.0.0-43-generic | 预编译，无工具/头文件 | 开 | 64/64，卸载重启通过 | [状态](ubuntu-24.04-hwe/result.json) · [介质](ubuntu-24.04-hwe/image.json) · [计算](ubuntu-24.04-hwe/workload.txt) · [签名](ubuntu-24.04-hwe/trust.txt) · [窗口 -22×4、-2×1](ubuntu-24.04-hwe/dmesg.txt) · [清理](ubuntu-24.04-hwe/cleanup.txt)。 本次镜像与 26.04 GA 的内核 release 可相同，预编译结果须按发行版内核区分。 |
| ubuntu-24.10-ga | 6.11.0-29-generic | 预编译 | 开 | 64/64，卸载重启通过 | [状态](ubuntu-24.10-ga/result.json) · [介质](ubuntu-24.10-ga/image.json) · [计算](ubuntu-24.10-ga/workload.txt) · [签名](ubuntu-24.10-ga/trust.txt) · [窗口 -22×4、-2×1](ubuntu-24.10-ga/dmesg.txt) · [清理](ubuntu-24.10-ga/cleanup.txt)。  |
| ubuntu-25.04-ga | 6.14.0-37-generic | 预编译 | 开 | 64/64，卸载重启通过 | [状态](ubuntu-25.04-ga/result.json) · [介质](ubuntu-25.04-ga/image.json) · [计算](ubuntu-25.04-ga/workload.txt) · [签名](ubuntu-25.04-ga/trust.txt) · [窗口 -22×4、-2×1](ubuntu-25.04-ga/dmesg.txt) · [清理](ubuntu-25.04-ga/cleanup.txt)。  |
| ubuntu-25.10-ga | 6.17.0-40-generic | 源码 | 开 | 64/64，卸载重启通过 | [状态](ubuntu-25.10-ga/result.json) · [介质](ubuntu-25.10-ga/image.json) · [计算](ubuntu-25.10-ga/workload.txt) · [签名](ubuntu-25.10-ga/trust.txt) · [窗口 -22×4、-2×1](ubuntu-25.10-ga/dmesg.txt) · [清理](ubuntu-25.10-ga/cleanup.txt)。  |
| ubuntu-26.04-ga | 7.0.0-43-generic | 源码 | 开 | 64/64，卸载重启通过 | [状态](ubuntu-26.04-ga/result.json) · [介质](ubuntu-26.04-ga/image.json) · [计算](ubuntu-26.04-ga/workload.txt) · [签名](ubuntu-26.04-ga/trust.txt) · [窗口 -22×4、-2×1](ubuntu-26.04-ga/dmesg.txt) · [清理](ubuntu-26.04-ga/cleanup.txt)。 7.0.0-43 与 HWE 同名但符号 CRC 不同，本地修订包回退到源码。[ABI 对照](ubuntu-26.04-ga/abi-comparison.txt)。 |
| ubuntu-26.10-ga | 7.3.0-10-generic | 源码 | 开 | 64/64，卸载重启通过 | [状态](ubuntu-26.10-ga/result.json) · [介质](ubuntu-26.10-ga/image.json) · [计算](ubuntu-26.10-ga/workload.txt) · [签名](ubuntu-26.10-ga/trust.txt) · [窗口 -22×4、-2×1](ubuntu-26.10-ga/dmesg.txt) · [清理](ubuntu-26.10-ga/cleanup.txt)。  |
| ubuntu-22.04-6.5 | — | — | — | 跳过 | 同一 LTS 的历史内核快照，按本轮范围跳过。 |
| debian-11 | — | — | — | 矩阵排除 | Packaged headers lack asm/hyperv-tlfs.h |
| debian-12 | 6.1.0-56-arm64 | 预编译 | 开 | 64/64，卸载重启通过 | [首轮实机记录](../arm64-devkit-2023/debian12-signed-ssh.txt)。 窗口 -22×4、-2×1。 |
| debian-13 | 6.12.118+deb13-arm64 | 预编译 | 开 | 64/64，卸载重启通过 | [首轮实机记录](../arm64-devkit-2023/debian13-signed.txt)。 窗口 -22×4、-2×1。 |
| debian-sid | 7.3.5+deb14-arm64 | 预编译，无工具/头文件 | 开 | 64/64，卸载重启通过 | [状态](debian-sid/result.json) · [介质](debian-sid/image.json) · [计算](debian-sid/workload.txt) · [签名](debian-sid/trust.txt) · [窗口 -22×4、-2×1](debian-sid/dmesg.txt) · [清理](debian-sid/cleanup.txt)。  |
| debian-testing | 7.3.5+deb14-arm64 | 预编译，无工具/头文件 | 开 | 64/64，卸载重启通过 | [状态](debian-testing/result.json) · [介质](debian-testing/image.json) · [计算](debian-testing/workload.txt) · [签名](debian-testing/trust.txt) · [窗口 -22×4、-2×1](debian-testing/dmesg.txt) · [清理](debian-testing/cleanup.txt)。  |
| debian-11-security-archive | — | — | — | 矩阵排除 | Packaged headers lack asm/hyperv-tlfs.h |
| debian-12-backports | 6.12.95+deb12-arm64 | 预编译，无工具/头文件 | 开 | 64/64，卸载重启通过 | [状态](debian-12-backports/result.json) · [介质](debian-12-backports/image.json) · [计算](debian-12-backports/workload.txt) · [签名](debian-12-backports/trust.txt) · [窗口 -22×4、-2×1](debian-12-backports/dmesg.txt) · [清理](debian-12-backports/cleanup.txt)。  |
| rocky-8 | 4.18.0-553.el8_10.aarch64 | 源码 | 开 | 未完成验收，阶段 install | [状态](rocky-8/result.json) · [介质](rocky-8/image.json) · [停点](rocky-8/install.txt)。 4.18 内核模块验证和安装器退出信息见 install.txt。 关闭安全启动另测原生用户空间，仍缺少 Qualcomm 库依赖，卸载重启通过。[动态链接器](rocky-8-native-off/loader-diagnostics.txt) · [清理](rocky-8-native-off/cleanup.txt)。 |
| rocky-9 | 5.14.0-741.22.1.el9_9.aarch64 | 首轮验收 | 开 | 64/64，卸载重启通过 | [首轮实机记录](../arm64-devkit-2023/rocky-signed.txt)。 窗口 -22×4、-2×1。 |
| rocky-10 | 6.12.0-264.16.1.el10_3.aarch64 | 源码 | 开 | 64/64，卸载重启通过 | [状态](rocky-10/result.json) · [介质](rocky-10/image.json) · [计算](rocky-10/workload.txt) · [签名](rocky-10/trust.txt) · [窗口 -22×4、-2×1](rocky-10/dmesg.txt) · [清理](rocky-10/cleanup.txt)。  |
| alma-8 | 4.18.0-553.187.1.el8_10.aarch64 | 预编译，无工具/头文件 | 开 | 未完成验收，阶段 install | [状态](alma-8/result.json) · [介质](alma-8/image.json) · [停点](alma-8/install.txt)。 MOK 已登记，4.18 内核给项目模块标记签名验证失败。原厂用户态库还要求 GLIBC_2.29 与 GLIBCXX_3.4.26。 关闭安全启动另测仍无法创建计算设备，卸载重启通过。[动态链接器](alma-8-native-off/loader-diagnostics.txt) · [清理](alma-8-native-off/cleanup.txt)。 |
| alma-9 | 5.14.0-741.22.1.el9_9.aarch64 | 源码 | 开 | 64/64，卸载重启通过 | [状态](alma-9/result.json) · [介质](alma-9/image.json) · [计算](alma-9/workload.txt) · [签名](alma-9/trust.txt) · [窗口 -22×4、-2×1](alma-9/dmesg.txt) · [清理](alma-9/cleanup.txt)。  |
| alma-10 | 6.12.0-264.16.1.el10_3.aarch64 | 源码 | 开 | 64/64，卸载重启通过 | [状态](alma-10/result.json) · [介质](alma-10/image.json) · [计算](alma-10/workload.txt) · [签名](alma-10/trust.txt) · [窗口 -22×4、-2×1](alma-10/dmesg.txt) · [清理](alma-10/cleanup.txt)。  |
| centos-stream-9 | 5.14.0-765.el9.aarch64 | 预编译，无工具/头文件 | 关 | 64/64，卸载重启通过 | [状态](centos-stream-9/result.json) · [介质](centos-stream-9/image.json) · [计算](centos-stream-9/workload.txt) · [签名](centos-stream-9/trust.txt) · [窗口 -22×4、-2×1](centos-stream-9/dmesg.txt) · [清理](centos-stream-9/cleanup.txt)。  |
| centos-stream-10 | 6.12.0-284.el10.aarch64 | 预编译，无工具/头文件 | 关 | 64/64，卸载重启通过 | [状态](centos-stream-10/result.json) · [介质](centos-stream-10/image.json) · [计算](centos-stream-10/workload.txt) · [签名](centos-stream-10/trust.txt) · [窗口 -22×4、-2×1](centos-stream-10/dmesg.txt) · [清理](centos-stream-10/cleanup.txt)。  |
| oracle-8 | — | — | — | 矩阵排除 | Oracle supplies UEK only on Arm; RHCK unavailable |
| oracle-8-uek | 5.15.0-326.224.5.2.el8uek.aarch64 | 预编译，无工具/头文件 | 开 | 未完成验收，阶段 workload | [状态](oracle-8-uek/result.json) · [介质](oracle-8-uek/image.json) · [计算](oracle-8-uek/workload.txt) · [签名](oracle-8-uek/trust.txt) · [窗口 -22×8、-2×2](oracle-8-uek/dmesg.txt) · [停点](oracle-8-uek/workload.txt)。 发行版 UEK 补装 Hyper-V 模块并修复引导条目后，签名模块加载成功。原厂 UMD 要求 GLIBC_2.29，计算设备创建返回 0x887a0004。[加载器诊断](oracle-8-uek/loader-diagnostics.txt)。 |
| oracle-9 | — | — | — | 矩阵排除 | Oracle supplies UEK only on Arm; RHCK unavailable |
| oracle-9-uek | 6.12.0-204.92.4.2.el9uek.aarch64 | 源码 | 开 | 64/64，卸载重启通过 | [状态](oracle-9-uek/result.json) · [介质](oracle-9-uek/image.json) · [计算](oracle-9-uek/workload.txt) · [签名](oracle-9-uek/trust.txt) · [窗口 -22×4、-2×1](oracle-9-uek/dmesg.txt) · [清理](oracle-9-uek/cleanup.txt)。 使用与 UEK 内核匹配的官方 GCC Toolset 14。 |
| fedora-41 | 6.11.4-301.fc41.aarch64 | 源码 | 关 | 64/64，卸载重启通过 | [状态](fedora-41/result.json) · [介质](fedora-41/image.json) · [计算](fedora-41/workload.txt) · [签名](fedora-41/trust.txt) · [窗口 -22×4、-2×1](fedora-41/dmesg.txt) · [清理](fedora-41/cleanup.txt)。  |
| fedora-42 | 6.14.0-63.fc42.aarch64 | 源码 | 关 | 64/64，卸载重启通过 | [状态](fedora-42/result.json) · [介质](fedora-42/image.json) · [计算](fedora-42/workload.txt) · [签名](fedora-42/trust.txt) · [窗口 -22×4、-2×1](fedora-42/dmesg.txt) · [清理](fedora-42/cleanup.txt)。  |
| fedora-43 | 6.17.1-300.fc43.aarch64 | 源码 | 关 | 64/64，卸载重启通过 | [状态](fedora-43/result.json) · [介质](fedora-43/image.json) · [计算](fedora-43/workload.txt) · [签名](fedora-43/trust.txt) · [窗口 -22×4、-2×1](fedora-43/dmesg.txt) · [清理](fedora-43/cleanup.txt)。  |
| fedora-44 | 7.3.4-200.fc44.aarch64 | 首轮验收 | 开 | 64/64，卸载重启通过 | [首轮实机记录](../arm64-devkit-2023/fedora-signed.txt)。 窗口 -22×4、-2×1。 |
| fedora-rawhide | 7.4.0-0.rc3.261119g4405c18c95d2.29.fc46.aarch64 | 预编译，无工具/头文件 | 开 | 64/64，卸载重启通过 | [状态](fedora-rawhide/result.json) · [介质](fedora-rawhide/image.json) · [计算](fedora-rawhide/workload.txt) · [签名](fedora-rawhide/trust.txt) · [窗口 -22×4、-2×1](fedora-rawhide/dmesg.txt) · [清理](fedora-rawhide/cleanup.txt)。 滚动仓库已提供 7.4 候选内核，表中使用真机 uname。 |
| anolis-8 | 4.18.0-553.186.1.0.1.an8.aarch64 | 预编译 | 关 | 未完成验收，阶段 workload | [状态](anolis-8/result.json) · [介质](anolis-8/image.json) · [计算](anolis-8/workload.txt) · [签名](anolis-8/trust.txt) · [窗口 -22×4、-2×1](anolis-8/dmesg.txt) · [清理](anolis-8/cleanup.txt) · [停点](anolis-8/workload.txt)。 官方 RHCK 启动后加载模块，原生用户空间缺少 Qualcomm 用户态驱动要求的 GLIBC_2.29 / GLIBCXX_3.4.26。[动态链接器输出](anolis-8/loader-diagnostics.txt)。 |
| anolis-23 | 6.6.102-8.0.2.an23.aarch64 | 预编译 | 关 | 64/64，卸载重启通过 | [状态](anolis-23/result.json) · [介质](anolis-23/image.json) · [计算](anolis-23/workload.txt) · [签名](anolis-23/trust.txt) · [窗口 -22×4、-2×1](anolis-23/dmesg.txt) · [清理](anolis-23/cleanup.txt)。 官方镜像缺少 hv_netvsc。使用同发行版 6.6.102-8.0.2 和本地 UDF 在来宾内执行安装、普通用户计算和清理。[三次启动 ID](anolis-23/boots.txt) · [准备记录](anolis-23/provisioning.txt)。 |
| openeuler-22.03-lts | — | — | — | 矩阵排除 | Packaged headers lack asm/hyperv-tlfs.h |
| openeuler-24.03-lts | — | — | — | 矩阵排除 | Packaged kernel does not export vmbus_open |
| opencloudos-8 | — | — | — | 矩阵排除 | 5.4.241 oc8 lacks pin_user_pages_fast |
| opencloudos-9 | 6.6.119-52.7.oc9.aarch64 | 源码 | 关 | 64/64，卸载重启通过 | [状态](opencloudos-9/result.json) · [介质](opencloudos-9/image.json) · [计算](opencloudos-9/workload.txt) · [签名](opencloudos-9/trust.txt) · [窗口 -22×4、-2×1](opencloudos-9/dmesg.txt) · [清理](opencloudos-9/cleanup.txt)。  |
| amazon-2023 | — | — | — | 矩阵排除 | 6.1 and 6.12.115 lack exported VMBus symbols |
| azure-3.0 | 6.6.161.1-1.azl3 | 预编译，无工具/头文件 | 开 | 64/64，卸载重启通过 | [状态](azure-3.0/result.json) · [介质](azure-3.0/image.json) · [计算](azure-3.0/workload.txt) · [签名](azure-3.0/trust.txt) · [窗口 -22×4、-2×1](azure-3.0/dmesg.txt) · [清理](azure-3.0/cleanup.txt)。 官方 VHDX 自带 dxgkrnl。先实测系统模块，再在测试差分盘备份并隔离它，验收部署包模块后恢复原件并核对摘要。[系统模块计算](azure-3.0/azure-stock.txt) · [恢复记录](azure-3.0/azure-restore.txt)。 |
| mariner-2.0 | — | — | — | 跳过 | 公开 MCR minimal-os 镜像的 SPDX 架构为 x86_64。未取得可匿名下载的通用 ARM64 安装盘或 Hyper-V VHD。[上游镜像说明](https://github.com/microsoft/azurelinux/issues/4059) |
| suse-15.5 | 5.14.21-150500.55.88-default | 预编译 | 开 | 64/64，卸载重启通过 | [状态](suse-15.5/result.json) · [介质](suse-15.5/image.json) · [计算](suse-15.5/workload.txt) · [签名](suse-15.5/trust.txt) · [窗口 -22×4、-2×1](suse-15.5/dmesg.txt) · [清理](suse-15.5/cleanup.txt)。 15.5 云盘的旧内核缺匹配开发包。安装同版仓库的 -55.88 内核、配套开发包及 SUSE shim，再启用 Secure Boot 实测。 |
| suse-15.6 | 6.4.0-150600.23.103-default | 首轮验收 | 开 | 64/64，卸载重启通过 | [首轮实机记录](../arm64-devkit-2023/leap-signed.txt)。 窗口 -22×4、-2×1。 |
| suse-16.0 | 6.12.0-160000.41-default | 预编译，无工具/头文件 | 开 | 64/64，卸载重启通过 | [状态](suse-16.0/result.json) · [介质](suse-16.0/image.json) · [计算](suse-16.0/workload.txt) · [签名](suse-16.0/trust.txt) · [窗口 -22×4、-2×1](suse-16.0/dmesg.txt) · [清理](suse-16.0/cleanup.txt)。  |
| suse-tumbleweed | 7.3.5-1-default | 预编译，无工具/头文件 | 开 | 64/64，卸载重启通过 | [状态](suse-tumbleweed/result.json) · [介质](suse-tumbleweed/image.json) · [计算](suse-tumbleweed/workload.txt) · [签名](suse-tumbleweed/trust.txt) · [窗口 -22×4、-2×1](suse-tumbleweed/dmesg.txt) · [清理](suse-tumbleweed/cleanup.txt)。 以同一仓库的完整 kernel-default 替换缺少 UDF/Hyper-V PCI 模块的基础内核。 |
| suse-slowroll | — | — | — | 矩阵排除 | No native kernel-default-devel in the configured Slowroll repositories |
| archlinuxarm | — | — | — | 矩阵排除 | Packaged kernel does not export vmbus_open |
| kali | 7.2.15+kali-arm64 | 预编译，无工具/头文件 | 关 | 64/64，卸载重启通过 | [状态](kali/result.json) · [介质](kali/image.json) · [计算](kali/workload.txt) · [签名](kali/trust.txt) · [窗口 -22×4、-2×1](kali/dmesg.txt) · [清理](kali/cleanup.txt)。 官方 Kali 云盘另装 Kali rolling 通用内核，来宾报告 7.2.15+kali-arm64，镜像仅提供 GRUB EFI。 |
| omv | 6.1.0-56-arm64 | 预编译，无工具/头文件 | 开 | 64/64，卸载重启通过 | [状态](omv/result.json) · [介质](omv/image.json) · [计算](omv/workload.txt) · [签名](omv/trust.txt) · [窗口 -22×4、-2×1](omv/dmesg.txt) · [清理](omv/cleanup.txt)。 在官方 Debian 12 ARM64 基座上安装并初始化 OpenMediaVault 7，版本见 prepare.txt。 |
| deepin-arm64 | 6.18.38-arm64-desktop-rolling | 源码 | 关 | 64/64，卸载重启通过 | [状态](deepin-arm64/result.json) · [介质](deepin-arm64/image.json) · [计算](deepin-arm64/workload.txt) · [签名](deepin-arm64/trust.txt) · [窗口 -22×4、-2×1](deepin-arm64/dmesg.txt) · [清理](deepin-arm64/cleanup.txt)。 Deepin 25.3 安装介质的 6.6.159 HWE 禁用 PCI_HYPERV、HYPERV_NET。另用 Deepin 官方签名 Crimson 仓库安装 6.18.38 rolling、配套开发包和本发行版模块，并以最小存储 initramfs 引导同一发行版根文件系统。固件拒绝该发行版当前的 ARM64 shim。[默认和 rolling 配置](deepin-arm64/distribution-kernels.txt) · [EFI 与软件包](deepin-arm64/firmware-packages.txt)。 |
| kylin | 7.0.0-4-generic | 源码 | 关 | 64/64，卸载重启通过 | [状态](kylin/result.json) · [介质](kylin/image.json) · [计算](kylin/workload.txt) · [签名](kylin/trust.txt) · [窗口 -22×4、-2×1](kylin/dmesg.txt) · [清理](kylin/cleanup.txt)。 openKylin 3.0 SP1 安装盘的 7.0.0-4-generic 使用 initcall_blacklist=i8042_init 启动。默认飞腾 D3000M 的 OpenCL ICD 在 Adreno 虚拟机崩溃，原始 D3D12 已回读 64/64，完整 verify 另测移开该 ICD 的配置。[首次输出](kylin/stock-opencl/workload.txt) · [ICD 包归属](kylin/stock-opencl/icd-selection.txt)。 |
| armbian | — | — | — | 跳过 | 矩阵标为上游基座，本轮未用面向具体板卡的镜像替代通用 Hyper-V 来宾。 |
| raspios64 | — | — | — | 跳过 | 树莓派物理板卡镜像，矩阵标为上游基座。 |
| arm-server | — | — | — | 跳过 | 矩阵为 Ubuntu 24.04 的通用服务器基座别名，无独立发行版镜像。 |
| devuan | 6.12.117+deb13-arm64 | 源码 | 开 | 64/64，卸载重启通过 | [状态](devuan/result.json) · [介质](devuan/image.json) · [计算](devuan/workload.txt) · [签名](devuan/trust.txt) · [窗口 -22×4、-2×1](devuan/dmesg.txt) · [清理](devuan/cleanup.txt)。 官方 Excalibur，PID 1 为 init。udevadm 对 PCI add 解析出 kmod load dxgkrnl，重新触发后设备归 video 组。移除规则内的加载命令后也可自动加载，说明还有其他加载路径。[规则对照](devuan/trust.txt)。 |
| gentoo | 6.18.64-p1-gentoo-dist-bin | 预编译 | 关 | 64/64，卸载重启通过 | [状态](gentoo/result.json) · [介质](gentoo/image.json) · [计算](gentoo/workload.txt) · [签名](gentoo/trust.txt) · [窗口 -22×4、-2×1](gentoo/dmesg.txt) · [清理](gentoo/cleanup.txt)。 云镜像未保留匹配的开发树。采用上游 Manifest 校验配套的 Gentoo 二进制发行内核和头文件，实际启动 -dist-bin 内核。[内核与摘要](gentoo/paired-kernel.txt)。 |

[宿主清理核对](host-cleanup.json)

## 专项记录

[MMIO 原值、两种配置及原始 strace 路径](mmio-trace/sampling.md) · [本机 ARM64 单元测试](native-unit-tests.txt)

Linux 发行版原有的 OpenCL ICD 和 glibc 版本会影响最终 verify 的退出码。各次未通过的原始日志保留在对应条目目录。

Ubuntu 26.04 GA 另外验证了更新内核，完整日志保留在 [7.0.0-44 对照](ubuntu-26.04-ga-current/)。每个测试目录含介质来源及摘要。派生云盘和安装介质的步骤单列，源码安装按需使用发行版原生工具链。
