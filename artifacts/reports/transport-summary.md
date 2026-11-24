# Hyper-V 单卡传输通道实测

每栏链接到绑定该物理适配器后普通用户 SSH 读出的内核与 VMBus class_id。仅在同一次采集出现全局通道和虚拟 GPU 通道时列入。

|来宾与运行内核|Intel Iris Xe|NVIDIA RTX 2060|
|---|---|---|
|arch · 7.3.4-arch1-2|[通道已枚举](transport-arch-760c9bb2/adapter-1.txt)|[通道已枚举](transport-arch-760c9bb2/adapter-0.txt)|
|debian-12 · 6.1.0-56-amd64|[通道已枚举](transport-debian-12-d5746313/adapter-1.txt)|[通道已枚举](transport-debian-12-d5746313/adapter-0.txt)|
|fedora-44 · 6.19.10-300.fc44.x86_64|[通道已枚举](transport-fedora-44-bfb56166/adapter-0.txt)|[通道已枚举](transport-fedora-44-e4cf0aeb/adapter-0.txt)|
|leap-15.6 · 6.4.0-150600.23.146-default|[通道已枚举](transport-leap-15.6-2ce77ad3/adapter-1.txt)|[通道已枚举](transport-leap-15.6-2ce77ad3/adapter-0.txt)|
|rocky-9 · 5.14.0-741.22.1.el9_9.x86_64|[通道已枚举](transport-rocky-9-44df25d9/adapter-1.txt)|[通道已枚举](transport-rocky-9-44df25d9/adapter-0.txt)|
|ubuntu-22.04 · 5.15.0-203-generic|[通道已枚举](transport-ubuntu-22.04-6a2f7961/adapter-0.txt)|[通道已枚举](transport-ubuntu-22.04-751db182/adapter-0.txt)|
|ubuntu-24.04 · 6.8.0-147-generic|[通道已枚举](ubuntu-pci-intel.txt)|[通道已枚举](ubuntu-pci-nvidia.txt)|
