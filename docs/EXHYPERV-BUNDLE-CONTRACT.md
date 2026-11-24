# ExHyperV 合盘契约 v1

每个 Release 提供 linuxpv-bundle-x86_64-VERSION.zip、linuxpv-bundle-aarch64-VERSION.zip、纯源码 ZIP 与 SHA256SUMS。先按清单校验完整 ZIP。Windows OSArchitecture 的 X64 对应 x86_64，Arm64 对应 aarch64。检查 ZIP 根的 manifest.json，拒绝不匹配的 arch 或不支持的 schemaVersion。

```json
{
  "schemaVersion": 1, "arch": "aarch64", "version": "v1.0.0",
  "libraries": {"libdxcore.so":"<sha256>", "libd3d12.so":"<sha256>", "libd3d12core.so":"<sha256>"},
  "probeSha256":"<sha256>",
  "kernels":[{"arch":"aarch64","release":"<uname -r>","name":"dxgkrnl","vermagic":"<modinfo -F vermagic>","srcversion":"<modinfo -F srcversion>","sha256":"<sha256>","targets":["debian-12"]}]
}
```

将 ZIP 解到新的暂存目录。保留 lib/、kernel/、guest/、prebuilt/index.json、prebuilt/ARCH/RELEASE/dxgkrnl.ko 和 LICENSE。prebuilt/index.json 与 manifest.kernels 相同。ELF 为小端 64 位，x86_64 的 e_machine 为 62，aarch64 为 183；模块为 ET_REL，运行库为 ET_DYN，探针可为 ET_EXEC 或 ET_DYN。

对每个已分配的 GPU，读取实际 PnP 驱动软件键、主和伴随 INF，将原厂目录完整复制至 drivers/PackageDir。带 NTamd64 或 NTarm64 装饰的 INF Directory/CopyFiles 节按宿主架构筛选。lib/ 采用 INF 的 lxss 别名，若同包的原文件名被 INF 用作加载器别名，真实厂商文件仍保留在 drivers/PackageDir 下。其余 Linux ELF（包括组件驱动）按文件名导出。合并不同显卡、伴随组件或微软运行库时，已有同名文件只接受相同 SHA-256，冲突立即报错。按 ELF 头选择架构，不能从 INF 文件夹中的 amd64 或 arm64 字符串推断文件架构。

在根目录写 device.json。每个对象描述一张已绑定的物理 GPU，同型号重复时以完整 PnP 设备标识选卡。

```json
{"schemaVersion":1,"arch":"x86_64","adapters":[{"device":"PCI\\VEN_8086&DEV_9A49...","name":"Intel Iris Xe","version":"32.0.101.6876","package":"iigd_dch.inf_amd64_..."}]}
```

生成卷标 GPUPV 的 UDF 光盘，校验目标 VM 的 GPU 分区集合与用户选择相同后挂载。PowerShell 示例：

```powershell
./host/gpupv-host.ps1 list
./host/gpupv-host.ps1 iso -Bundle .\linuxpv-bundle-x86_64-v1.0.0.zip -Gpu @('NVIDIA GeForce RTX 2060','Intel(R) Iris(R) Xe Graphics') -Output .\local.iso -VMName 'your-vm'
```

来宾单行安装：

```sh
sudo mkdir -p /mnt/gpupv && { mountpoint -q /mnt/gpupv || sudo mount -o ro "$(sudo blkid -L GPUPV)" /mnt/gpupv; } && sudo sh /mnt/gpupv/guest/setup
```

已录入 MOK 或关闭 Secure Boot 时可一次完成。首次录入由管理员在 shim 菜单确认。安装后以 video 组普通用户执行 `gpupv-guest verify`，可选视频步骤使用 `--with-video`。卸载执行 `sudo gpupv-guest uninstall`。光盘上的私有宿主 UMD 仅用于该宿主的部署；公开源码归档与按架构发布的微软运行库部署包分别生成。
