# Windows Dev Kit 2023 上的 ARM64 GPU-PV 实测

2026-11-25 在 Windows 11 Pro Insider Preview build 29671 上测试。Hyper-V 将 Qualcomm Adreno 8cx Gen 3 列为可分区设备，显示驱动为 30.0.4122.4000。Linux 来宾通过 hv_pci 枚举到 1414:008e，DXCore 读出的物理适配器为 4d4f4351:36333630。数值测试由 video 组普通用户执行，D3D12 Dispatch 写入 64 个整数并全部读回比对。[宿主设备和厂商库摘要](host.json)

| 来宾和安装方式 | 验证结果 |
| --- | --- |
| Debian 12，6.1.0-56-arm64，正式 RC1 光盘 | 命中预编译模块，Secure Boot 关闭，计算 64/64。[原始输出](release-unsigned.txt) |
| Debian 12，同一内核，本地修订光盘 | 首次安装要求登记 MOK。登记后重复安装成功，签名者为 GPU-PV module signing。来宾重启后模块 taint 为 O，普通用户计算 64/64。[安装](signed-install.txt) · [重启与内核日志](signed-reboot.txt) |
| Debian 12，SSH 推送 | 卸载并重启后，宿主通过 SSH 推送本地修订包，再次签名加载、核对适配器、回读 64/64 并卸载。[重启清理](uninstall.txt) · [SSH 部署](signed-ssh.txt) · [独立 SSH 矩阵的签名重启与卸载](debian12-signed-ssh.txt) |
| Ubuntu 24.04，6.8.0-147-generic，源码编译 | 用 ubuntu-ports 仓库补齐对应的 linux-modules-extra、头文件和 GCC。光盘安装器从源码构建模块，计算 64/64。[编译与计算](ubuntu-source.txt) |
| Ubuntu 24.04，同一内核，DKMS | 使用同一光盘注册并编译 DKMS 模块，重启后加载 updates/dkms/dxgkrnl.ko.zst，计算 64/64，卸载后 DKMS 记录和设备节点均已清理。[注册与编译](ubuntu-dkms.txt) · [重启与卸载](ubuntu-dkms-reboot.txt) |
| Ubuntu 24.04，同一内核，最终版签名 DKMS | 第一版使用项目密钥后，Ubuntu DKMS 另行生成发行版密钥，非交互安装卡在登记提示。最终版在编译前提示登记 DKMS 实际使用的 shim 密钥。新建来宾完成登记、无交互编译安装、签名重启、普通用户回读 64/64 和卸载重启。[修正前](ubuntu-dkms-before-fix.txt) · [最终版验收](ubuntu24-signed-dkms.txt) |
| Ubuntu 22.04，6.8.0-149-generic | GA 5.15.0-203 即使安装 modules-extra 也缺少 pci_hyperv。切换到发行版 HWE，签名重启、计算 64/64、卸载重启均通过。[HWE 验收](ubuntu22-hwe.txt) |
| Debian 13，6.12.118+deb13-arm64 | 预编译模块签名重启、计算 64/64、卸载重启均通过。另在该来宾从源码构建 AArch64 探针，再次得到相同结果。[签名验收](debian13-signed.txt) · [原生探针及查询跟踪](native-probe.txt) |
| Fedora 44，7.3.4-200.fc44.aarch64 | 原始云镜像启动时提示 Security Violation。在一次性来宾中更新官方 shim、GRUB、内核后重新开启 Secure Boot，签名重启、计算 64/64、卸载重启均通过。[初始画面](fedora-first-boot.png) · [启动包版本](fedora-secure-boot.txt) · [签名验收](fedora-signed.txt) |
| Rocky Linux 9，5.14.0-741.22.1.el9_9.aarch64 | 签名重启、计算 64/64、卸载重启均通过。[签名验收](rocky-signed.txt) |
| openSUSE Leap 15.6，6.4.0-150600.23.103-default | 使用仓库可成对安装的内核和开发包，通过 ARM64 的 /boot/Image 文件识别候选内核。签名重启、计算 64/64、卸载重启均通过。[签名验收](leap-signed.txt) |
| Alpine 3.23.4，6.18.22-0-virt | 安装器识别 musl 后以退出码 1 结束，未创建安装目录。独立的传输测试在该镜像枚举到 GPU-PV 所需的 VMBus 设备。[负向测试](alpine-negative.txt) · [VMBus 枚举](alpine-transport.txt) |

## 地址空间和日志

七个 glibc 发行版与版本组合均在开启 Secure Boot 的来宾内完成签名模块加载、计算和卸载重启。每组计算后的内核日志都出现四次 -22 和一次 -2，严格零错误验收为 0/7。测试结束后宿主保留 13 台已注册虚拟机，本次临时来宾为零。宿主上次启动为 11 月 12 日。[宿主清理记录](host-cleanup.json)

该宿主的新建来宾默认高位 MMIO 窗口为 512 MiB。使用默认值，dxgkrnl 报告 `Unable to allocate mmio memory: -6`。直接将大小改为 32 GiB，Hyper-V 会在初始化内存时返回 0x80070057。将基址和大小一起设为 32 GiB，得到 32–64 GiB 的高位窗口，宿主能够启动来宾，模块能够分配 MMIO。这个布置已在本机的 2 GiB 和 3 GiB 测试来宾验证。

在 Debian 12 的签名重启计算窗口，内核记录一次 feature 查询 -22、三次 type 1 查询 -22（宿主 0xc000000d），以及一次 type 48 查询 -2（宿主 0xc0000034）。同一进程随后完成了 64 项回读。计算验收通过，严格的内核零错误项仍有这些记录。[带调用类型的原始日志](signed-reboot.txt)

在 Debian 13 的原生 AArch64 探针进程中，glibc 审计输出进一步定位到 adapter=0 的 feature 268435456 查询、KMTUMDVERSION 0/1/2，以及 DXCoreWSLAttributes 注册表查询。审计器记录实际调用并保留返回值。该诊断与安装、计算和清理结果分别记录。[原生调用跟踪](native-probe.txt)

## 介质与校验

两个本地候选版本均复用通过正式 RC1 整包 SHA-256 校验的 ARM64 模块和探针。第一版修正适配器身份核对。最终版 `v0.1.0-rc1.arm64-local.2` 又修正 Ubuntu DKMS 在 Secure Boot 下选择签名密钥的流程。正式包和两个本地版本均与仓库锁表的 44 个目标记录、118 个内核 release 逐项一致。三份微软运行库、探针及模块通过 ELF 架构、类型和摘要检查，以 x86_64 校验最终 ARM64 包时按预期被拒绝。最终版的四项 Linux 回归测试在原生 ARM64 来宾通过。[模块池核对](bundle-pool.txt) · [回归输出](regression.txt)

| 文件 | SHA-256 |
| --- | --- |
| 正式 linuxpv-bundle-aarch64-v0.1.0-rc1.zip | e538a8ddfccdc46e0eb91a9488804491d3e4864f15df3ac0232161d32071db51 |
| linuxpv-bundle-aarch64-v0.1.0-rc1.arm64-local.zip | c5f5ae8ebbbe20b998c615b5e6ec27413045f40b96d183cf40484734c38ea1be |
| gpupv-adreno-arm64.iso | 1d974232ec915e313756be1df21a8dcbbfc21f3cd80f50c2eb8e4e6e105134d9 |
| linuxpv-bundle-aarch64-v0.1.0-rc1.arm64-local.2.zip | 1dafbb0a47068cde52e0ded4093acd3b33bb0d0afc83b12adb25d1b715396023 |
| gpupv-adreno-arm64-r2.iso | 899b31b834d11e5f837b98ff84d1a2fea77d3f5f61ab41c13f4dff004a478821 |

ISO 包含本机 Qualcomm DriverStore 文件，适用于此宿主和驱动版本。预编译池中的 118 个 release 均已核对二进制，硬件运行覆盖以上述逐项测试为准。
