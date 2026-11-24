
Caption                : Microsoft Windows 11 专业版
Version                : 10.0.26200
BuildNumber            : 26200
OSArchitecture         : 64 位
TotalVisibleMemorySize : 16469676


Manufacturer        : Intel(R) Client Systems
Model               : NUC11PHi7
TotalPhysicalMemory : 16864948224
HypervisorPresent   : True


Name : D
Used : 143106359296
Free : 368449826816


Name          : OrayIddDriver Device
DriverVersion : 16.54.44.444
PNPDeviceID   : ROOT\DISPLAY\0000

Name          : Intel(R) Iris(R) Xe Graphics
DriverVersion : 27.20.100.8935
PNPDeviceID   : PCI\VEN_8086&DEV_9A49&SUBSYS_20908086&REV_01\3&11583659&0&10

Name          : Microsoft Remote Display Adapter
DriverVersion : 10.0.26100.9818
PNPDeviceID   : SWD\REMOTEDISPLAYENUM\RDPIDD_INDIRECTDISPLAY&SESSIONID_0001

Name          : NVIDIA GeForce RTX 2060
DriverVersion : 32.0.16.1742
PNPDeviceID   : PCI\VEN_10DE&DEV_1F15&SUBSYS_20908086&REV_A1\4&2498E50C&0&0030


Status   Name               DisplayName
------   ----               -----------
Running  vmcompute          Hyper-V 主机计算服务
Running  vmms               Hyper-V 虚拟机管理

Name              : Hyper-V
Path              : C:\Windows\system32\WindowsPowerShell\v1.0\Modules\Hyper-V\2.0.0.0\Hyper-V.psd1
Description       : 
Guid              : af4bddd0-8583-4ff2-84b2-a33f5c8de8a7
Version           : 2.0.0.0
ModuleBase        : C:\Windows\system32\WindowsPowerShell\v1.0\Modules\Hyper-V\2.0.0.0
ModuleType        : Manifest
PrivateData       : 
AccessMode        : ReadWrite
ExportedAliases   : {[gvm, gvm], [savm, savm], [spvm, spvm], [gvmr, gvmr]…}
ExportedCmdlets   : {[Add-VMAssignableDevice, Add-VMAssignableDevice], [Add-VMDvdDrive, Add-VMDvdDrive], [Add-VMFibreChannelHba, Add-VMFibreChannelHba], [Add-VMGpuPartitionAdapter, Add-VMGpuPartitionA
                    dapter]…}
ExportedFunctions : {}
ExportedVariables : {}
NestedModules     : {}

Elevated: True


Name                 : \\?\PCI#VEN_10DE&DEV_1F15&SUBSYS_20908086&REV_A1#4&2498e50c&0&0030#{064092b3-625e-43bf-9eb5-dc845897dd59}\GPUPARAV
ValidPartitionCounts : {32}

Name                 : \\?\PCI#VEN_8086&DEV_9A49&SUBSYS_20908086&REV_01#3&11583659&0&10#{064092b3-625e-43bf-9eb5-dc845897dd59}\GPUPARAV
ValidPartitionCounts : {32}


Name           SwitchType
----           ----------
Default Switch   Internal
C:\Windows\System32\lxss\lib\libd3d12.so False
C:\Windows\System32\lxss\lib\libd3d12core.so False
C:\Windows\System32\lxss\lib\libdxcore.so False
C:\Program Files\WSL\lib\libd3d12.so False
C:\Program Files\WSL\lib\libd3d12core.so False
C:\Program Files\WSL\lib\libdxcore.so False
dotnet C:\Program Files\dotnet\dotnet.exe
go 
cargo 
gcc 
cl 
docker 
wsl C:\Windows\system32\wsl.exe
python C:\Users\Administrator\AppData\Local\Microsoft\WindowsApps\python.exe
git C:\Program Files\Git\cmd\git.exe
qemu-img 
ssh C:\Windows\System32\OpenSSH\ssh.exe
tar C:\Windows\system32\tar.exe
oscdimg 



Name                                           Architecture
----                                           ------------
11th Gen Intel(R) Core(TM) i7-1165G7 @ 2.80GHz            9


实际测试已补充工具：仓库隔离目录内使用 QEMU 11.1 qemu-img。系统 PATH 中的 python 为 WindowsApps 别名，构建改用本机工作区 Python。宿主未安装 WSL 发行环境，容器编译运行在新建的 Debian Hyper-V VM 内。
PowerShell 7.6.9
git version 2.56.0.windows.4
10.0.403 [C:\Program Files\dotnet\sdk]
Python 3.12.14
qemu-img version 11.1.0 (v11.1.0-12130-ge470268ff4)
Copyright (c) 2003-2026 Fabrice Bellard and the QEMU Project developers
