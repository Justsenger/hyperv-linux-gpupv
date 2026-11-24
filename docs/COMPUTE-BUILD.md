# 双架构 Compute 构建和发布

`targets/matrix.json` 每条包含目标 id、arch 列表、原生容器 image、family、packages 和可选 repo。scope 为 upstream-base 时，产物仅对应实际头文件的内核版本，使用衍生版自有内核的机器需匹配自己的内核。ARM64 Arch 使用社区维护的 menci/archlinuxarm 容器，原生 ARM64 runner 从 Arch Linux ARM 仓单独取 linux-aarch64-headers。x64 官方 Arch 使用 archlinux 镜像。Gentoo 输入必须有配置和 Module.symvers。构建脚本依据内核配置选择 LLVM。编译探针会拒绝缺少 pin_user_pages_fast 的内核，包含该接口回移的旧版本内核按实际头文件判断。

查看计划或在与目标同架构的 Linux Docker 主机实际运行一个目标：

```sh
python3 tests/container-matrix.py --plan
python3 tests/container-matrix.py --arch x86_64 --target debian-12 --output out
sh guest/build-probe ./probe
python3 build.py bundle --arch x86_64 --version v1.0.0 --pool out --probe ./probe --output-dir dist/phase1
python3 build.py --output-dir dist/phase1
```

正式 CI 的探针在 AlmaLinux 8 的 glibc 2.28 上原生编译，静态链接 C++ 运行库。每个目标产生模块、模块摘要、srcversion、vermagic 和对应目标名。相同 release 有不同二进制时合包会中止。预编译命中还需运行内核接受模块的配置和符号版本，最终加载结果由 modprobe 判断。

定制内核可以添加以下目标。将示例 URL 和摘要替换为发布者实际值；tar 内是已准备好的内核构建树，包含 Makefile、generated headers 和 Module.symvers。deb 或 rpm 由相应发行版包管理器安装依赖。

```json
{"id":"nas-kernel","arch":["aarch64"],"image":"debian:12","family":"deb","packages":[],"headers":{"format":"tar","url":"https://example.org/kernel-headers.tar","sha256":"<64位十六进制摘要>"}}
```

私有矩阵可用 --matrix 指定。Refresh native module artifacts 在原生 Linux runner 编译适用目标。Compute bundles 从经校验的模块池生成双架构部署包，并在两个包均通过检查后生成源码包与 SHA256SUMS。


公开源码包排除微软二进制。部署包根据 host/wsl-runtime.json 固定提交和 SHA-256 收集对应架构的三份微软专有运行库。宿主物理 GPU 的 UMD 在本机合盘时加入。使用、分发微软或厂商二进制按各自许可执行。

本地特权容器验收脚本为 `tests/prebuilt-container`。它需要独占一台可弃置的 GPU-PV 来宾的内核。容器中挂入真实 GPUPV 光盘、/dev、只读 /sys 和 /run/udev，使用 Debian 12 的 python3、kmod、udev、openssl、mokutil。Secure Boot 开启时将该测试机已登记的密钥目录只读挂入来宾内的测试容器。脚本核查无 GCC/make/当前内核头文件，实际加载模块、重复安装并卸载。普通用户计算和重启持久性在该 VM 本身验证。

TrueNAS 24.10.2.4 与 25.04.2.6 两个目标使用 TrueNAS 包索引公布的 production-amd64 头文件和 SHA-256，发布时可以替换为新的精确版本。默认只读 appliance 不在来宾安装范围内。[TrueNAS 官方开发环境说明](https://www.truenas.com/docs/scale/25.04/scaletutorials/systemsettings/advanced/developermode/)

构建矩阵按架构选用原生容器。系统仓索引取自发行方，Pop!_OS 使用发布方标明的签名指纹。[Pop!_OS 仓库](https://apt.pop-os.org/) · [OpenCloudOS 容器镜像](https://docs.opencloudos.org/OCS/Install_Guide/ocs-docker/) · [Ubuntu 历史快照](https://ubuntu.com/server/docs/how-to/software/snapshot-service/)

在独占的可弃置双卡 VM 内复现容器实装。以下命令假设光盘已挂载，VM 本身的 gpupv-guest 已卸载，且测试 MOK 已登记。

```sh
sudo docker build -t linuxpv-prebuilt-test - <<'EOF'
FROM debian:12
RUN apt-get update && apt-get install -y --no-install-recommends python3 kmod udev mokutil openssl
EOF
sudo docker run --rm --privileged \
  -v /sys:/sys:ro -v /dev:/dev -v /run/udev:/run/udev \
  -v /mnt/gpupv:/media/gpupv:ro -v /var/lib/gpupv-signing:/var/lib/gpupv-signing:ro \
  -v "$PWD/tests/prebuilt-container:/test:ro" linuxpv-prebuilt-test sh /test
```

在已安装驱动的测试 VM 中，以普通用户执行 `sh tests/compute-acceptance "$HOME/compute-log"` 收集数值结果与该窗口内核日志。RTX 2060 + Iris Xe、CUDA 和 Intel OpenCL 均已就绪时，`sh tests/isolate-dual-compute` 会单独运行 NVML、D3D12、CUDA、OpenCL，将各自的输出、退出码和内核日志写入 `$HOME/compute-isolated/`。测试用户需能执行非交互 sudo 来标记和读取内核日志。

## 已验证模块池与发布

`targets/prebuilt-pool.json` 固定每个架构与内核 release 的生产作业、目标名和模块 SHA-256。打包作业从本仓库的 Actions artifacts 恢复这些文件，逐个校验后生成部署包。相同架构和 release 只收录一份；编译次数和发行版别名不增加模块数量。修改 kernel 源树或生产 artifacts 过期时需使用 Refresh native module artifacts 手动构建并更新锁表。保留正式 ZIP 和 SHA256SUMS 可长期离线部署。每次推送 compute-preflight 分支或手动运行 Compute bundles 可验证成品；推送 v 开头标签才触发 GitHub Release，带连字符的标签标记为 prerelease。

`targets/matrix.json` 中 excluded 记录每个架构退出默认编译门槛的原因。OpenCloudOS 8 缺少页固定接口。Debian 11 与 openEuler 22.03 的 ARM64 头文件缺少 Hyper-V 架构头；openEuler 24.03、Arch Linux ARM、Amazon Linux 2023 的已测 ARM64 内核缺少 VMBus 导出。Oracle ARM64 仅提供 UEK，Slowroll ARM64 仓库缺少原生开发包，这两项按发行方供包情况单列。
