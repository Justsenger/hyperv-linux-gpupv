# 上游基线
|来源|采用或规避的做法|
|---|---|
|[WSL2-Linux-Kernel](https://github.com/microsoft/WSL2-Linux-Kernel/tree/a07f9ea8a99139913acbcc1c160b132cb2a49c81/drivers/hv/dxgkrnl)|固定 6.6 分支提交，保留内核模块与配套 UAPI 头。6.18 是另一条上游基线，不能据此推断普通 Linux 来宾的兼容性。|
|[libdxg](https://github.com/microsoft/libdxg)|MIT 用户态辅助库访问设备，内核通道仍由 dxgkrnl 提供。|
|[staralt](https://github.com/staralt/dxgkrnl-dkms)|6.6 补丁涉及 eventfd、任务名、fence 回调和重映射时的写锁。将接口分歧转换为面向目标头文件的编译探针。|
|[thexperiments](https://github.com/thexperiments/dxgkrnl-dkms-git)|PKGBUILD 单独收集驱动和 UAPI，改造外部模块 Makefile。整份替换 hyperv.h 会引入结构体布局风险。|
|[MBRjun](https://github.com/MBRjun/dxgkrnl-dkms-lts)|extra-defines.h 单独补充 VMBus 设备 GUID，避免替换目标内核的 Hyper-V 类型。|
|[Nislaco](https://github.com/Nislaco/Linux-GPU-V-Scripts-for-Hyper-V)|分发行版脚本提供构建案例和宿主资源路径，不能证明同家族所有内核均可编译。|
|[seflerZ](https://github.com/seflerZ/oneclick-gpu-pv)|ubuntu-gpu-pv.ps1 涵盖双库目录、适配器选择、vgem 与 VA 前端。环境变量应限于验证进程。|
|[AppSandbox](https://github.com/jamesstringer90/appsandbox)|tools/linux/asb_drm 提供 DRM/KMS 显示通路；项目单独记录 asb-dxgkrnl 和定制 Mesa 的来源。桌面运行时应在独立前缀部署，当前仅探测已有图形栈。|

内核部分保留逐文件 SPDX 和原始版权声明。基础运行库与厂商包只在最终用户宿主机生成本地载荷，不纳入公开源码发行包。各参考仓库本次检出的提交见 reports 中的 upstream-revisions.txt。
## 构建来源与许可
本次检出的 staralt 源码附 GPL v2；thexperiments 和 MBRjun 的 PKGBUILD 声明 GPL2。Nislaco 和 seflerZ 此次检出的仓库根目录均未见许可文件，本项目仅对照其路径、安装流程和公开说明。AppSandbox 顶层代码采用 MIT，内核组件及定制 Mesa 各自保留上游许可。版本号见 [检出的提交](../artifacts/reports/upstream-revisions.txt)。

6.6 基线内最后一处按内核版本判断的路径涉及 VMBus 通道的 max_pkt_size。该路径已改为编译成员赋值探针，以覆盖厂商反向移植。编译器实际暴露的 VMBus remove 回调差异单独探测。
AppSandbox 的 dxgkrnl 清单固定到微软 6.18.58.1 上游；Mesa 清单明确指定 Ubuntu 26.04 amd64、压缩包 SHA-256 和 asbDrmInterfaceVersion 1。若将来引入桌面包，需要为来宾 ABI、Mesa 版本与 DRM 接口共同建立验收记录。当前实现仅在验证进程中设置 Mesa 选择变量，并扫描系统的多架构 DRI 目录和 Dozen ICD 清单。[dxgkrnl 清单](https://github.com/jamesstringer90/appsandbox/blob/6c684666bd8b9771229340e17962706bcb774776/vendor/dxgkrnl/source-version.json) · [Mesa 清单](https://github.com/jamesstringer90/appsandbox/blob/6c684666bd8b9771229340e17962706bcb774776/vendor/mesa-d3d12/source-version.json)

libdxg 的 d3dkmt-wsl.cpp 将 WDDM 调用转为设备 ioctl，构建还用到 DirectX-Headers。它可用于专门的用户态诊断；当前工具保留宿主驱动实际需要的三项 WSL 库作为独立硬性前置条件。[Microsoft libdxg](https://github.com/microsoft/libdxg/tree/5c28ebb4ead460c23ec5e87decb7d1af7285bb59)
