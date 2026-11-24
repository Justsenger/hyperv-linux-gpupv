# hyperv-linux-gpupv · 第一阶段计算版

将 Windows Hyper-V 分区 GPU 提供给可写的 glibc Linux 来宾。一个虚拟机可以使用一张或多张 GPU。宿主机无需安装 WSL。按宿主架构选择 `linuxpv-bundle-x86_64-<version>.zip` 或 `linuxpv-bundle-aarch64-<version>.zip`，用同批 `SHA256SUMS` 校验。当前试构建的 x86_64 和 aarch64 部署包分别包含 166 和 118 个预编译内核版本。[本轮实测及覆盖范围](COMPATIBILITY.md)

## 安装

1. 用 ExHyperV 配置 GPU 分区，选择与 Windows 宿主匹配的部署包并挂载它合成的 GPUPV 光盘。使用本仓宿主工具时，在管理员 PowerShell 7.4+ 中运行下例，将包路径、GPU 名称和虚拟机名称替换为本机值。
2. 在来宾安装 Python 3、glibc、kmod、udev，并将需要计算的普通用户加入 `video` 组后重新登录。预编译模块精确匹配运行内核时可直接安装。未匹配时需安装当前内核头文件、make 和对应 GCC/Clang 工具链。Secure Boot 来宾另需 shim、mokutil 和 OpenSSL。
3. 在来宾执行下方光盘命令。若安装器提示登记 MOK，执行屏幕给出的导入命令，重启进入 MOK Manager，选择 Enroll MOK 并确认。回到系统后重新挂载光盘执行安装。密钥和登记只需办理一次。

```powershell
./host/gpupv-host.ps1 list
$b = './dist/phase1/linuxpv-bundle-x86_64-phase1-local.2.zip'
$cards = 'NVIDIA GeForce RTX 2060','Intel(R) Iris(R) Xe Graphics'
./host/gpupv-host.ps1 doctor -Bundle $b
./host/gpupv-host.ps1 iso -Bundle $b -Gpu $cards -Output ./gpu.iso -VMName '你的虚拟机'
```

```sh
sudo mkdir -p /mnt/gpupv && sudo mount -o ro -L GPUPV /mnt/gpupv && sudo sh /mnt/gpupv/guest/setup
```

已挂载时直接执行 `sudo sh /mnt/gpupv/guest/setup`。SSH 已配置公钥、主机密钥及非交互 sudo 的来宾也可运行 `./host/gpupv-host.ps1 push -Gpu $cards -Bundle $b -Destination user@vm`。部署完成后由登录用户执行设备检查。

本机已经合成并实测的 RTX 2060 + Iris Xe 双卡 UDF 位于 `dist/local-media/`，同目录有独立摘要。该光盘包含本机 DriverStore 厂商文件，仅用于本机来宾部署。公开发版使用 `dist/phase1/` 中的两个架构包和源码包。

## 验证和卸载

```sh
gpupv-guest doctor
gpupv-guest verify
sudo gpupv-guest uninstall
```

卸载会清理已登记的模块、设备规则、开机配置及本工具的运行库链接。来宾本地 MOK 密钥和固件信任记录保留，供管理员继续使用。

普通用户运行 verify 会实际打开 /dev/dxg，逐个测试硬件 DXCore/D3D12 计算适配器并读回 64 个数值。来宾有 NVIDIA 管理工具时查询驱动与显存，有 CUDA 运行库时执行 CUDA 运算，有 OpenCL GPU ICD 时执行 OpenCL 运算。视频组件按需用安装和验证命令的 `--with-video` 开关启用。[此前的视频实测](docs/2026-11-24-video-release.md)

驱动来自当前 Windows 主机；微软三份运行库按 host/wsl-runtime.json 的提交和摘要写入对应架构部署包，公开源码包只含源码、文档和报告。微软和 GPU 厂商二进制各自适用其专有许可。使用纯源码方式构建来宾探针需要支持 C++17 的 g++。宿主工具在源码模式下可用 `-WslLibDir <目录>` 或显式执行 `./host/gpupv-host.ps1 fetch-wsl-libs -Arch x86_64`。

[ExHyperV 合盘接口](docs/EXHYPERV-BUNDLE-CONTRACT.md) · [双架构构建、定制内核与发布命令](docs/COMPUTE-BUILD.md) · [本轮原始证据](artifacts/reports/phase1)
