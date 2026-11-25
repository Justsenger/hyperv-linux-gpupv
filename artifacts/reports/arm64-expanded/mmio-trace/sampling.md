# ARM64 Adreno 的 ExHyperV 实测参数

测试使用 Windows Dev Kit 2023、Windows build 29671、Qualcomm Adreno 8cx Gen 3 驱动 30.0.4122.4000，以及本地 ARM64 部署包合成的 UDF 光盘。来宾为 Debian 12，内核 `6.1.0-56-arm64`，启动内存 2048 MiB。以下配置仅涉及测试来宾。

| 布置（MiB） | 高位基址 | 高位大小 | 高位结束地址（不含） | 低位大小 |
| --- | ---: | ---: | ---: | ---: |
| 新建第 2 代 VM 的原始默认值 | 65024 | 512 | 65536 | 512 |
| 上一轮已通过的向下扩展配置 | 32768 | 32768 | 65536 | 512 |
| 本轮实测的 ExHyperV 配置 | 32768 | 31744 | 64512 | 3584 |

高位窗口的原始上界为 `E = 默认基址 + 默认大小`。上一轮设置 `base = E − 32768 MiB`、`size = 32768 MiB`。本轮保持这个基址，再从高位大小扣除 1024 MiB，顶部保留区间为 [64512, 65536) MiB。Hyper-V PowerShell 的内存属性以字节计，WMI 的 `HighMmioGapBase`、`HighMmioGapSize` 和 `LowMmioGapSize` 以 MiB 计。65536 MiB 是这台机器的地址窗口上界。[默认属性](mmio-default.json) · [PowerShell 设置后读数](host-mmio.txt) · [WMI 设置后读数](wmi-mmio.json)

来宾枚举到 `1414:008e`，未安装 gcc、make 及当前内核头文件。Secure Boot 开启，MOK 登记并重启后，dxgkrnl 已签名加载，普通用户获得 `/dev/dxg` 读写权限。对 `4d4f4351:36333630` 的 D3D12 Dispatch 比对通过 64/64。卸载后再次重启，受管理路径清理通过。计算采样窗口出现四次 -22 和一次 -2。[环境](environment.txt) · [模块签名](trust.txt) · [计算](workload.txt) · [内核采样](dmesg.txt) · [清理](cleanup.txt)

## 文件访问

普通用户运行 `strace -f -yy -s 4096 -e trace=file -o /tmp/gpupv-files.trace /opt/hyperv-linux-gpupv/guest/d3d12-compute`。跟踪中的计算同样回读 64/64。`-f` 跟踪子进程，`-yy` 标注打开后文件描述符对应的路径。表中是成功打开的全部 `/usr/lib/wsl/` 文件，类型来自同一来宾的 `file` 输出。[原始系统调用](strace-file.txt) · [跟踪中的计算输出](traced-workload.txt) · [文件类型](traced-tree.txt)

| 成功打开的来宾路径 | 类型 |
| --- | --- |
| `/usr/lib/wsl/lib/libdxcore.so` | AArch64 ELF |
| `/usr/lib/wsl/lib/libd3d12.so` | AArch64 ELF |
| `/usr/lib/wsl/lib/libd3d12core.so` | AArch64 ELF |
| `/usr/lib/wsl/drivers/qcdx8280.inf_arm64_ce29b34c1ddc2154/libqcdx12arm64wslum.so` | AArch64 ELF |
| `/usr/lib/wsl/drivers/qcdx8280.inf_arm64_ce29b34c1ddc2154/libqcdxarm64wslcompiler.so` | AArch64 ELF |

本次计算未观察到成功打开非 ELF 固件或数据文件。原始日志保留加载器对可选路径的失败查找，包括 D3DDriverVerifier.dll。采样覆盖此版本驱动的计算进程。GPU 固件在 Windows 宿主或内核内部的读取，以及视频、图形工作负载所需文件，均不在此进程的跟踪范围内。
