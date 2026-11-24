# 数据流与验证边界

Windows CLI 使用 Get-VMHostPartitionableGpu 枚举实例，并通过 PnP 绑定的 INF 获取 DriverStore 目录。ELF 头校验覆盖 64 位、字节序、共享对象类型和机器号。按活动适配器的注册表值、主 INF 与 CopyINF 扫描 Linux 伴随组件。每个包保存所选适配器对应的驱动目录、基础库、设备清单、来宾工具与 GPL 驱动源码。归档通过 OpenSSH 标准输入传输。ISO 使用 Windows IMAPI2FS。

来宾安装先执行一秒限时只读体检，再复制源码到临时目录。Kbuild 使用目标内核的配置编译 C 探针，生成私有头文件。Linux 发行版名称不参与 API 选择。内核源码也提供 DKMS 配置，默认安装使用运行内核的 Kbuild 产物。

安装将运行库和驱动放入专用目录，建立 /usr/lib/wsl、模块路径、udev、modules-load、modprobe 和 ld.so.conf.d 对应链接。已有目标路径会触发冲突保护。安装状态记录创建的父目录以支持清理。video 组与桌面 uaccess 管理设备权限。内核更新后需重新构建。Intel 的 VA-API 测试选用发行版 Mesa D3D12 后端，通过 vgem 提供无桌面 DRM 节点。

内核模块生成、加载、普通用户权限、重启、自检和实际工作负载是不同证据。CUDA 探针在匹配设备名称后运行 PTX 乘加并回读结果。Intel 探针选择 DXCore 硬件适配器，在 D3D12 队列中提交计算着色器，等待 fence，校验 64 个结果。具备 OpenCL ICD 的基座还会执行独立计算校验。视频测试强制使用硬件帧并统计解码输出。最终支持状态仅由实测日志决定。
## 使用 DKMS
来宾预装 DKMS 时，可执行 `sudo python3 /mnt/guest/gpupv-guest install --dkms`。该模式将同一套源码注册为 gpupv-dxgkrnl/0.1，后续内核使用自己的头文件重新执行 conftest。默认 Kbuild 安装只服务当前内核。两种模式共用卸载命令。

## 复现实测
在专用 Linux 构建 VM 上运行 `python3 tests/container-matrix.py` 可下载发行版官方容器并编译全部目标。预备好本地头文件时，`sh tests/compile-matrix 标签=/绝对路径/build` 可离线编译。容器测试记录源树摘要、镜像标签、头文件版本、modinfo 及模块摘要。软件仓库更新会改变实际头文件版本。

`tests/Get-CloudImage.ps1` 从指定官方来源下载镜像并核对 HTTPS 发布的 SHA-256/512。此步骤未另行验证离线 GPG 签名。`tests/New-TestVM.ps1` 使用该镜像、便携 qemu-img 和测试用 Ed25519 公钥创建 Gen2 VM。`tests/Test-CloudTransport.ps1` 逐卡检查 VMBus 通道。`tests/Invoke-Acceptance.ps1` 面向拥有本地 ID 记录的测试 VM，执行完整重启、非 root 工作负载与卸载验收；只有最后一步成功才写入通过记录。

在 2026-11-23 的 Debian 13 隔离 VM 中，DKMS 使用来宾生成的密钥签名，shim MOK 管理器完成入库，mokutil --test-key 返回已登记。Secure Boot 关闭时，加载模块的内核仍报告签名或所需密钥缺失。签名动作、固件登记和内核信任分别记录。该试验未更改 Windows 宿主证书或驱动。

2026-11-24 的 Debian 13 使用 Microsoft UEFI CA 模板和 Secure Boot，通过 shim 将来宾 MOK 导入内核 .machine 密钥环，并由 .secondary_trusted_keys 引用。原生安装的 sign-file 和 DKMS 的签名命令均有实测记录。签名后的内核模块仍带有外部模块标志 O。MOK 留在来宾以便内核升级后签名；卸载驱动不会撤销管理员登记的证书。详见 [MOK 信任链](../artifacts/reports/2026-11-24/pilot-mok-trust.txt) 与 [DKMS 实际签名](../artifacts/reports/2026-11-24/pilot-dkms.txt)。
