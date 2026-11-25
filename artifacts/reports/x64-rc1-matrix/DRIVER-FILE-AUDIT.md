# Debian 12 双卡计算文件访问审计

环境为 Debian 12、6.1.0-56-amd64、RTX 2060 和 Iris Xe。普通用户分别在 strace -f -yy -s 2048 -e trace=file 下执行三种计算负载。记录 /usr/lib/wsl/ 及其指向的 /opt/hyperv-linux-gpupv/lib 和 drivers；进程访问的发行版系统库在原始跟踪中保留。

D3D12、CUDA 与 OpenCL 均完成数值校验，退出码均为 0。

## 成功打开的唯一文件

|负载|厂商|文件类型|按解析路径去重|
|---|---|---|---:|
|cuda|Microsoft|ELF|1|
|cuda|NVIDIA|ELF|4|
|cuda|NVIDIA|other|1|
|d3d12|Intel|ELF|6|
|d3d12|Microsoft|ELF|3|
|d3d12|NVIDIA|ELF|2|
|opencl|Intel|ELF|1|
|opencl|Microsoft|ELF|1|

## 非 ELF 文件

- NVIDIA · other · `/opt/hyperv-linux-gpupv/drivers/nvinsi.inf_amd64_bdbfdf54ab096b2b/nvcubins.bin`

## DriverStore 逻辑文件字节数

|厂商|原始字节|PE 字节|去 PE 后字节|减少|
|---|---:|---:|---:|---:|
|NVIDIA|2,838,605,324|1,922,662,344|915,942,980|67.73%|
|Intel|2,319,737,545|1,885,459,096|434,278,449|81.28%|

按 DOS 头的 e_lfanew 和 PE 签名识别 Windows 二进制；去 PE 后保留 ELF 及全部其他数据。统计采用宿主驱动目录的逻辑字节，未制作精简 ISO，也没有用删减后的驱动复测。一次负载未访问的文件仍可能被其他驱动版本、设备或负载使用。


## 实体副本测量

从当前宿主 DriverStore 在同一个 NTFS 卷创建完整临时副本，复核逐文件大小及 PE 签名，再在该副本内实际剔除 PE。两次遍历分别读取文件数、逻辑长度和 Windows 报告的 AllocationSize。临时二进制副本已删除。

|厂商|完整文件数|剔除后文件数|完整已分配字节|剔除后已分配字节|
|---|---:|---:|---:|---:|
|Intel|174|40|2,320,060,704|434,348,320|
|NVIDIA|214|64|2,839,057,792|916,067,712|


[按负载、厂商及路径查看全部文件访问](file-access.csv)
