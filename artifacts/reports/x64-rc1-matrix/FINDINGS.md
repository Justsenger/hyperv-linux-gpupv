# 首轮计算层观察

以下记录对应 v0.1.0-rc1。相同内核版本的 ABI 选择与 Ubuntu DKMS 签名已单独复核，见[定点复核结果](REPORT.md)。

|环境|首轮实测|
|---|---|
|Debian 12，RTX 2060 单卡、Iris Xe 单卡、双卡|三种拓扑都由 video 组普通用户运行。双卡各 64/64，NVIDIA CUDA 得到 38、136、892。安装 Intel GPU ICD 后 Intel OpenCL 校验 32 个结果。|
|Debian 12，按负载记录 dmesg|D3D12 与 CUDA 的单独采样窗口没有 -75。Intel OpenCL 数值正确，其窗口中出现两次 dxgkio_reserve_gpu_va 的 -75。|
|优先的八个基座|Debian 12/13、Ubuntu 22.04/24.04、Fedora 44、Rocky 9、Arch、Leap 15.6 各有双卡 Secure Boot 开启、模块被信任、零签名告警和卸载重启记录。另有八个基座各自实际命中预编译、无 gcc/make/headers 的测试。Fedora 的 Secure Boot 测试运行 6.19.10-300.fc44，而免编译测试运行 7.3.4-200.fc44。|
|Leap 15.6|发行版默认第三方模块策略拒绝加载。使用仓库现有测试脚本临时允许第三方模块；关闭或开启 Secure Boot 与该策略是两个独立条件。已在 6.4.0-150600.23.103-default 上通过签名双卡验收并恢复原策略。|
|Arch 的两条路径|7.3.5-arch1-1 使用预编译模块、MOK 和 UKI。7.3.4-arch1-2 使用匹配头文件进行源码/DKMS 回退。两者均通过双卡计算与卸载闭环。|
|CachyOS 内核与 Arch 用户空间|官方 7.3.5-2-cachyos 命中预编译；6.18.60-3-cachyos-lts 为 GCC 内核；6.12.69-2-cachyos-lts-lto 的运行内核明确启用 CONFIG_CC_IS_CLANG 和 CONFIG_LTO_CLANG_THIN。LTO 来宾通过 DKMS 编译、双卡读回和卸载。|
|Ubuntu 26.04 的 7.0.0-43-generic|PCI 枚举两张 1414:008e。部署包命中且 vermagic 字符串匹配，但 modprobe 返回 Exec format error，运行内核报告 dxgkrnl disagrees about version of symbol module_layout。|
|Ubuntu 26.10 的 7.3.0-10-generic|预编译未命中。实际部署使用源码路径，重启后两张卡均数值通过。|
|AlmaLinux 8.10 的 4.18.0-553.187.1.el8_10.x86_64|RTX 2060 单独挂载，D3D12 与 CUDA 通过。Iris Xe 单独挂载和双卡配置均在 Intel D3D12CreateDevice 返回 0x887a0004。来宾 glibc 2.28；从实际访问的 Intel ELF 中读取到 libigc.so 和 libLLVM-14.so 对 libm 的 GLIBC_2.29 引用。此静态差异是已知依赖条件，未单独证明它是 HRESULT 的唯一原因。|
|Amazon Linux 2023 的 6.1.190-237.442.amzn2023.x86_64|已有匹配的 kernel-modules-extra，但系统内核未启用 CONFIG_PCI_HYPERV，无法提供 GPU-PV 所需的 PCI 通道。|
|Azure Linux 3.0、CBL-Mariner 2.0|两者都自带发行版的 dxgkrnl，部署包保护现有模块。Azure Linux 3.0 的 6.6.161.1-1.azl3 用原生模块和离线包用户态库，普通用户独立探针通过双卡 64/64 及 CUDA。Mariner 的 5.15.202.1-1.cm2 同样用原生模块通过两张卡各 64/64 及 CUDA 三个数值。首次运行由于标准目录缺少普通用户搜索权限而失败，补全目录权限后复测通过。|
|openEuler、OpenCloudOS|openEuler 22.03 SP4（5.10.0-216.0.0.115.oe2203sp4）及 24.03 SP2（6.6.0-98.0.0.103.oe2403sp2）都在官方系统盘上通过双卡计算与卸载。两个 openEuler 来宾先由独立救援盘配置 SSH，移除救援盘后再启动。OpenCloudOS 9 使用 6.6.119-52.7.oc9 和源码回退，也完成闭环。|
|Anolis OS 23.4|官方 6.6.102-8.0.2.an23 命中预编译，双卡计算、重复安装、卸载重启通过。发行版 libpwquality 软件包依赖 make，RPM 拒绝卸载。标准镜像保留 gcc/make。另在专用一次性镜像中明确移除工具、允许 libpwquality 的 RPM 依赖未满足，安装前核实无 gcc/make/headers，双卡全闭环通过。此人为精简条件只用于验证预编译路径。|
|Ubuntu 20.04 HWE 双卡 UDF|5.15.0-139-generic 命中预编译池，两个 hv_pci 设备已绑定。内核 UDF 阅读器在目录 inode 298、偏移 2012 报错，安装器读取 lib/nvidia-smi 返回 errno 117。NVIDIA 单卡介质也能复现。另用 Debian genisoimage 制作 UDF，经双 UDF 挂载逐路径及内容比较一致，Focal 复测仍在同一文件失败（目录 inode 319）。|
|Devuan Excalibur 非 systemd 启动|官方安装介质安装 SysV init 和 eudev 3.2.14，升级到 6.12.118+deb13-amd64 命中预编译。部署后真实重启，普通用户在任何手动 modprobe 之前即可读写 root:video 0660 的 /dev/dxg。双卡 64/64、CUDA 以及卸载重启通过。专项复测在数值验收之后，对两个实际 1414:008e PCI 设备分别执行 udevadm test。两者均命中 70-gpupv.rules 第 2 行的 kmod load dxgkrnl，系统 80-drivers.rules 也匹配模块别名。|
|Ubuntu 24.04 HWE|7.0.0-44-generic 的预编译模块也出现 module_layout 校验失败。对照 Ubuntu 26.04 GA：同样的 uname -r、同一份 SHA-256 为 c49eb05f… 的预编译模块，在 26.04 的 7.0.0-44-generic 通过全闭环，在 24.04 的 7.0.0-44.44~24.04.1 无法加载。再用 Ubuntu 24.04 官方 HWE 7.0.0-43.43~24.04.1 对照，7.0.0-43-generic 在 HWE 双卡通过，而同名 26.04 GA 内核拒载。只按架构和 uname -r 查表不能区分这两组 ABI。|
|Oracle Linux 9 RHCK 与 UEK|RHCK 和 UEK 都在官方发行版来宾完成双卡闭环。UEK 6.12.0-208.112.5.3.el9uek 的源码回退需要匹配编译器：系统 GCC 11 不识别内核选项 -fmin-function-alignment=16；使用 Oracle 仓库的 GCC Toolset 14 重新执行原包安装器后通过。|
|OpenMediaVault|通过 OMV 发行方签名仓库在真实 Debian 系统盘安装 openmediavault 7.7.24-7。OMV 重设了 SSH 的 AllowGroups，测试账号加入 _ssh 和 video 后可持续登录。两次安装、非 root 双卡计算、卸载重启通过。|
|openSUSE Leap 15.5、16.0 及 Tumbleweed|Leap 15.5 使用仓库中有匹配预编译模块的 5.14.21-150500.55.88-default。Leap 16.0 的精简云内核缺 UDF；从官方仓库安装完整 kernel-default 后，用 UDF 正常安装。Tumbleweed 同样在补齐 UDF 支持后通过。三者均已实测双卡及卸载重启。|
|Gentoo|云镜像初次启动 6.18.64-p1，没有适配的构建树。通过签名 Portage 快照安装官方 gentoo-kernel-bin，实际改启 6.18.64-p1-gentoo-dist-bin。先验算双卡，再在独立 VM 中用 Portage 卸掉编译工具、归档并移出展开的内核头文件，确认安装时均不可用。预编译、重复安装、重启计算、卸载重启通过。|
|openSUSE Slowroll|通过签名的 Slowroll 发行仓库迁移 Tumbleweed 云镜像。来宾已记录 openSUSE-release 的 sr 版本、Slowroll 的 os-release 身份，双卡实际读回并完成卸载重启。|
|Rocky Linux 8|4.18.0-553.el8_10.x86_64 源码编译通过。双卡时 Intel D3D12CreateDevice 返回 0x887a0004，NVIDIA 单独挂载完成 64/64、CUDA 及卸载重启。|
|Kali Rolling|官方云盘默认跟随 kali-last-snapshot，初次使用 7.1.5+kali-cloud-amd64 的源代码安装失败。切换发行方签名的 kali-rolling 源，安装并显式启动 7.2.15+kali-amd64，命中预编译且安装前无工具链。普通用户双卡通过。|
|Anolis OS 8.10|官方云盘在为 Gen2 补齐启动驱动、配置自动网络后仍未建立可验收来宾。独立数据盘测试中，20 次短间隔采样记录了 12 次运行时间回退，Hyper-V Worker 事件 18514 记录来宾主动重置。已关闭此测试 VM；缺少可归因到某个内核函数的来宾日志。|
|Oracle Linux 8.10 RHCK 与 UEK|使用 Oracle 签名 RPM 在官方 KVM 模板中分别引导 4.18.0-553.189.1.el8_10.x86_64 和 5.15.0-326.224.5.2.el8uek.x86_64。二者均命中预编译池，重复安装后完成真实重启，uid 1000 的 video 组用户可访问 /dev/dxg。原包 verify 首先运行的 nvidia-smi 均报告找不到 libnvidia-ml.so 并返回 12，未进入后续数值探针。两者均执行卸载并再次重启。该信息不能单独定位底层加载失败的原因。|
|openEuler 22.03 / 24.03、Anolis 23、OpenCloudOS 9、Kali 的 Secure Boot|切换到 Hyper-V 面向 Linux 的 Microsoft UEFI 证书模板后，五组实际来宾启动盘都停在固件页，SCSI Disk 显示 “The unsigned image’s hash is not allowed (DB)”。未进入这些镜像的 Linux 或 MOK 阶段。五者关闭 Secure Boot 后的原生双卡计算闭环已另行取证。|
|Rocky 8、Alma 8 的 NVIDIA 单卡 Secure Boot|旧版 mokutil 不接受设置超时的参数。测试改用固件默认超时后，来宾确认已提交 MOK 导入请求，但自动操作未识别到预期注册菜单。两者单卡数值通过的证据来自关闭 Secure Boot 的运行。|
|Ubuntu 25.04 的 Secure Boot 源码回退|在 Ubuntu 归档快照补齐 6.14.0-36-generic 的构建依赖，启动时已经录入项目生成的 MOK。发行版 DKMS 又生成一把未录入的密钥并停在 debconf 交互请求。仅在测试来宾中核对已录入证书的 DER 摘要后，让发行版 DKMS 默认密钥路径复用该密钥并关闭重复交互。随后原包完成安装、重装、重启双卡计算、卸载重启，签名告警为零。此结果依赖额外配置。|
