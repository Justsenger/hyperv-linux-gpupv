# x86_64 第一阶段纯计算真机验收

## 首轮覆盖

主机同时挂载 NVIDIA GeForce RTX 2060（32.0.16.1742）和 Intel Iris Xe（32.0.101.6876）。在 5eb3115 对应的 v0.1.0-rc1 部署逻辑上，66 个目标中有 45 个原生发行版目标完成 UDF 部署、重复安装、重启后普通用户双卡计算及卸载重启。36 个目标取得 Secure Boot + MOK 零签名告警的双卡证据。32 个验证了无 gcc、make 或当前内核头文件的预编译安装，16 个验证了源码回退，部分目标覆盖两条路径。

其余 21 项包括 2 个仅 NVIDIA 单卡完整通过、2 个用发行版原生模块通过双卡计算、1 个 CachyOS 内核和 Arch 用户空间混合环境、4 个进入来宾后未通过计算、1 个启动反复重置、3 个无原生来宾结果，以及 8 个历史、复用或只读目标。Debian 12 的双卡测试中，两条 -75 发生于 Intel OpenCL 窗口。

[首轮 66 项及内核](MATRIX-66.md) · [可筛选的 CSV](matrix-66.csv) · [发行版边界](FINDINGS.md) · [驱动文件审计](DRIVER-FILE-AUDIT.md)

## Ubuntu 定点复核

使用 f540b68（含 2a6defb）的安装器、原版 rc1 x86_64 预编译池、本机双卡驱动重新制作 UDF。来宾预先安装对应内核头文件和编译依赖。24.04 与 26.04 均保留同名冲突模块；25.04 使用 Ubuntu 2025-12-01 签名归档快照和 DKMS。验证均在重启后由 video 组普通用户运行。三项均已卸载并再次重启检查，测试 VM 与临时盘已移除。

|目标|实际内核|安装路径|重启后数值读回|
|---|---|---|---|
|Ubuntu 24.04 HWE|7.0.0-44-generic|检测到 kmalloc_caches (0xeb9f047a != 0x88f79fc5, pci_hyperv)，自动用运行内核头文件重新编译|双卡各 64/64，CUDA 38、136、892|
|Ubuntu 26.04 GA|7.0.0-43-generic|检测到 kmalloc_caches (0x2dcfc42e != 0xafbd0823, pci_hyperv)，自动用运行内核头文件重新编译|双卡各 64/64，CUDA 38、136、892|
|Ubuntu 25.04|6.14.0-36-generic|首次安装提示录入 Ubuntu shim MOK。在 MOK Manager 确认一次，重启后导出的 DER 与 /var/lib/shim-signed/mok/MOK.der 逐字节一致，DKMS 自动签名，重启后加载，签名告警 0 条|双卡各 64/64，CUDA 38、136、892|
