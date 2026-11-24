# 2026-11-24 Debian 13 双卡调用记录

测试机运行 Debian 13，内核 6.12.118+deb13-amd64。两张卡先后独占同一台 Hyper-V 来宾的 GPU 分区。两次安装均在启用 Secure Boot、确认 MOK 后执行。全部工作负载以 uid 1000 运行。

|调用|实测返回与发生位置|观测到的工作负载结果|
|---|---|---|
|Intel 查询适配器，类型 1|每次请求 524 字节，VMBus 返回 NTSTATUS 0xc000000d，映射为 -22|DXCore 枚举一个硬件适配器，64 项 D3D12 Compute 回读均正确|
|Intel 查询适配器，类型 48|请求 552 字节，VMBus 返回 0xc0000034，映射为 -2|同一进程完成计算|
|Intel IsFeatureEnabled|来宾返回 -22，当前采集未证明此项收到宿主状态|仍保留内核错误|
|NVIDIA NVML 清理和控制调用|strace 栈从 libnvidia-ml.so.1 的 nvmlEscapeRmFree / nvmlEscapeRmControl 经 libdxcore.so 的 D3DKMTEscape 进入 ioctl 0xc020470d。64 和 196 字节请求在获取来宾适配器锁前返回 -22。该路径上复制失败返回 -EFAULT，加锁遇到停用适配器返回 -ENODEV，因此当前源码中相符的是 dxgprocess_adapter_by_handle 未找到句柄|nvidia-smi 读到 617.42、6144 MiB|
|NVIDIA FFmpeg escape|适配器已锁定。VMBus 请求 139 字节，期望回复 68 字节，事务 1679 和 1724 均收到零字节，返回 -75。完整日志也包含 80 字节的私有数据请求|CUDA 三个测试值匹配，NVENC/CUVID 完成 15 帧|

process_completion_packet 必须验证实际回复长度再复制。主机返回零字节的原因尚无 Windows 厂商侧协议证据。严格内核日志验收仍未通过。

微软将 DRIVERPRIVATE 的缓冲区格式交由硬件厂商定义，并要求虚拟化场景清除 HardwareAccess。所记录的 NVIDIA 调用 flags=0 符合这一位的要求。WDDM 文档还描述了 SecureVirtualMachine 模式对私有 escape 的限制。本机 GraphicsDrivers 下未设置 GpuVirtualizationFlags，目前没有宿主 KMD 对该次调用报告 SecureVirtualMachine 的证据。因此未将全部失败归为宿主策略。[微软 escape 定义](https://learn.microsoft.com/en-us/windows-hardware/drivers/ddi/d3dkmthk/ns-d3dkmthk-_d3dkmt_escape) · [微软 GPU 半虚拟化文档](https://learn.microsoft.com/en-us/windows-hardware/drivers/display/gpu-paravirtualization) · [宿主只读记录](host-virtualization-flags.json)

微软下游对照版本见 [Git 引用](upstream-refs.txt) 与[源码摘要](upstream-files.txt)。原始记录见 [Intel 查询](pilot-dkms-compute.txt)、[NVIDIA VMBus 事务](pilot-rtx-dmesg.txt)、[NVML 调用栈](pilot-nvml-ioctl.txt)、[NVIDIA 工作负载](pilot-rtx-workload.txt)。

宿主机报告两张分区卡都有编解码预算。Ubuntu 24.04 Intel 实例的 CurrentPartitionEncode 和 CurrentPartitionDecode 都为 1000000000。该配置仍出现实际编码等待。[宿主能力](host-partition-capabilities.json) · [来宾分区预算](ubuntu24-intel-partition.json) · [下游源码函数对照](upstream-ioctl-comparison.txt)。

对已启用的 Windows DxgKrnl Admin 和 Operational 日志进行了只读核查。在记录的回归时间窗口内只见 CreateVirtualGpu（446、447）和 OpenVirtualGpu（454、455）事件，未取得可按该 Debian 13 测试 VM 的 ID 关联的私有 escape 返回事件。宿主拒绝原因的证据边界仍在 VMBus 回复长度及 NTSTATUS。[日志通道、时间窗与计数](host-dxg-events.json)

随后读取了 CreateVirtualGpu 事件自身的 bSecure 字段。08:55 至取样时的 88 条创建开始与完成事件均为 bSecure=false、NTSTATUS=0。对两台当时在线且启用 Secure Boot 的自有测试 VM，还按分区编号及前后 4 秒内带 VM GUID 的 Hyper-V 事件做了时间对照。这批 vGPU 创建没有启用上述 SecureVirtualMachine 私有 escape 限制。它不能解释本批回归的全部 -22 和 -75。[逐事件字段与两台来宾的时间对照](host-gpu-security-mode.json)

本机 Windows SDK 10.0.26100.0 将查询 1 定义为 KMTQAITYPE_UMDRIVERNAME，查询 48 定义为 KMTQAITYPE_QUERYREGISTRY。前者的 524 字节与版本字段及 260 个 UTF-16 字符的文件名数组相符，后者的 552 字节符合 x64 注册表查询结构的固定部分。微软说明 GPU-PV 的此类注册表请求经宿主处理。仅凭 0xc0000034 无法识别缺少的具体值。[本机 SDK 枚举值](query-type-mapping.txt) · [微软适配器查询类型](https://learn.microsoft.com/en-us/windows-hardware/drivers/ddi/d3dkmthk/ne-d3dkmthk-_kmtqueryadapterinfotype) · [微软注册表请求说明](https://learn.microsoft.com/en-us/windows-hardware/drivers/display/gpu-paravirtualization)

Fedora 44 中在验收内核日志采集完成后，再以普通用户运行同一个 D3D12 计算。调用观察器记录到查询 1 的三个 KMTUMDVERSION 依次为 0、1、2，对应 DX9、DX10、DX11。查询 48 指定适配器键、flags=0、值名 DXCoreWSLAttributes。本机 Intel 显示适配器软件键缺少该值，同时其 UserModeDriverNameWsl 文件存在。对应宿主返回 0xc0000034，随后仍成功创建 D3D12 设备并得到 64/64 项正确结果。feature=0x10000000 的查询使用零适配器句柄，在本机来宾的句柄查找处返回 -22。另一次普通用户 nvidia-smi 读到显存和版本后提交的三次 NVML escape 均使用同一非零句柄 0x40000080，载荷依次为 64、64、196 字节。[Intel 普通进程调用](../gpupv-test-ad23c26f92fb457980e9ef68d093b133-0c2e1ba4/dxcore-call-metadata.txt) · [宿主注册表检查](intel-query-registry.json) · [对应内核日志](../gpupv-test-ad23c26f92fb457980e9ef68d093b133-0c2e1ba4/dmesg-after-workload.txt) · [NVIDIA 普通进程调用](../gpupv-test-951008680583407685e5db901ea9b321-295d9b7b/dxcore-call-metadata.txt)

Rocky 9 上再用同一普通用户命令跟踪同一进程内的句柄生命周期。DXCore 枚举返回 0x40000000、0x40000040 和 0x40000080。nvidia-smi 打印显存后，先成功关闭 0x40000080，随后三个失败的 NVML escape 都继续使用已关闭的 0x40000080。源码的 dxgprocess_close_adapter 在成功关闭时从本进程句柄表删除该项，因此随后的查找会在来宾返回 -EINVAL。这给出了这三次错误的直接原因。FFmpeg 的 -EOVERFLOW 具有有效句柄并收到零字节回复，应单独追踪。[同进程按顺序记录的打开、关闭与失败调用](../gpupv-test-1c7f6a03a3d844fd874a1dbd11e20ec7-d0587375/dxcore-call-metadata.txt) · [NVML 栈](pilot-nvml-ioctl.txt) · [来宾句柄生命周期实现](../../../kernel/drivers/hv/dxgkrnl/dxgprocess.c)

### VMBus 长度的观测位置

事务 1679、1724 各有一条按事务 ID 匹配的 VM_PKT_COMP。139 字节是发送请求长度，68 字节是来宾预期的回复数据长度，0 是来宾 dxgkrnl 从完成描述符算出的有效载荷长度。微软下游的 hv_pkt_datalen 使用 (len8 - offset8) × 8。环形缓冲区迭代器在交付描述符前检查这两个字段并将检查后的值写入副本。两个字段在副本中相等即可得到零。本次日志未记录检查前的字段或宿主处理该请求的 NTSTATUS，因此无法由 received=0 判定宿主主动屏蔽了调用，也无法断言本次发生了字段修正。保留 -EOVERFLOW 可防止复制不足 68 字节的数据。[原始事务](pilot-rtx-dmesg.txt) · [微软下游长度定义](https://github.com/microsoft/WSL2-Linux-Kernel/blob/4ee82e228f384c4335f6b2048af72d6956f74c21/include/linux/hyperv.h#L1591-L1595) · [接收描述符检查](https://github.com/microsoft/WSL2-Linux-Kernel/blob/4ee82e228f384c4335f6b2048af72d6956f74c21/drivers/hv/ring_buffer.c#L434-L479)

### 最终 16 组内核日志逐项计数

只统计每个 ioctl 的最终失败行。动态跟踪同一事务的中间行不重复计入。

|调用|返回值|次数|
|---|---:|---:|
|dxgkio_escape|-22|48|
|dxgkio_escape|-75|162|
|dxgkio_is_feature_enabled|-22|90|
|dxgkio_query_adapter_info|-2|90|
|dxgkio_query_adapter_info|-22|270|
|dxgkio_reserve_gpu_va|-75|10|
|dxgkio_wait_sync_object_cpu|-512|14|

其中 Intel 的 GPU 虚拟地址预留也出现短回复。Fedora 44 的事务 290 由 python3 发出，请求 112 字节，来宾需要 16 字节结果，有效载荷为 0。另有 14 条同步等待失败，日志在相邻行记录 wait_completion_interruptible 返回 -512，属于内核可中断等待返回；日志没有单独记录发送信号的进程。[Fedora 44 原始日志](../gpupv-test-ad23c26f92fb457980e9ef68d093b133-0c2e1ba4/dmesg-after-workload.txt) · [逐组合计数](final-matrix.json)
