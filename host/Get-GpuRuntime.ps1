param([Parameter(Mandatory)]$Card,[Parameter(Mandatory)][string]$Store)
$ErrorActionPreference='Stop'
$inf=(Get-WindowsDriver -Online -Driver $Card.Inf | Select-Object -First 1).OriginalFileName
$primary=(Get-Item -LiteralPath $inf).Directory
if($primary.Parent.FullName -ne $Store){throw "Unexpected active INF location: $inf"}
$driverKey=(Get-PnpDeviceProperty -InstanceId $Card.Pnp -KeyName DEVPKEY_Device_Driver).Data
$reg=Get-Item -LiteralPath "HKLM:/SYSTEM/CurrentControlSet/Control/Class/$driverKey"
$packages=@{$primary.Name=$primary.FullName}
$values=[ordered]@{}
foreach($name in $reg.GetValueNames() | Where-Object {$_ -match 'WSL|OpenCLDriverName|LevelZeroDriverPath|DriverStorePathForComputeRuntime'}){
    $values[$name]=@($reg.GetValue($name))
    foreach($file in $values[$name]){
        if($file -notmatch '\.so(?:\.\d+)*$'){continue}
        if(!(Test-Path -LiteralPath $file -PathType Leaf)){continue}
        $actual=(Get-Item -LiteralPath $file).FullName
        if(!$actual.StartsWith($Store+'\',[StringComparison]::OrdinalIgnoreCase)){throw "Registered ELF outside DriverStore: $actual"}
        $packageName=$actual.Substring($Store.Length+1).Split('\')[0]
        $packages[$packageName]=Join-Path $Store $packageName
    }
}
$companions=@()
$children=@((Get-PnpDeviceProperty -InstanceId $Card.Pnp -KeyName DEVPKEY_Device_Children -ErrorAction SilentlyContinue).Data)
foreach($id in $children){
    if(!$id){continue}
    $child=Get-PnpDevice -InstanceId $id -PresentOnly -ErrorAction SilentlyContinue
    if(!$child -or $child.Class -ne 'SoftwareComponent'){continue}
    $componentInf=(Get-PnpDeviceProperty -InstanceId $id -KeyName DEVPKEY_Device_DriverInfPath -ErrorAction Stop).Data
    $component=(Get-WindowsDriver -Online -Driver $componentInf | Select-Object -First 1).OriginalFileName
    $directory=(Get-Item -LiteralPath $component).Directory
    if($directory.Parent.FullName -ne $Store){throw "Unexpected component INF location: $component"}
    $elf=@(Get-ChildItem -LiteralPath $directory.FullName -Recurse -File -Filter '*.so*' | Where-Object {$_.Name -match '\.so(?:\.[0-9]+)*$'})
    $companions+=[pscustomobject]@{child=$id;ref=$componentInf;package=$directory.Name;linuxFiles=@($elf | Select-Object -ExpandProperty Name)}
    if($elf.Count){$packages[$directory.Name]=$directory.FullName}
}
$directives=Select-String -LiteralPath $inf -Pattern '^\s*CopyINF\s*=\s*([^;]+)'
$refs=@($directives | ForEach-Object {$_.Matches[0].Groups[1].Value.Split(',')} | ForEach-Object {$_.Trim(' ','"')} | Sort-Object -Unique)
foreach($ref in $refs){
    if($ref -notmatch '^[\w.\\-]+\.inf$' -or [IO.Path]::IsPathRooted($ref) -or $ref.Split('\') -contains '..'){throw "Unexpected CopyINF entry: $ref"}
    $leaf=Split-Path -Leaf $ref
    $embedded=Join-Path $primary.FullName $ref
    $candidates=@(Get-ChildItem -LiteralPath $Store -Directory -Filter ($leaf+'_*') | Where-Object {Test-Path -LiteralPath (Join-Path $_.FullName $leaf)})
    if($candidates.Count -gt 1 -and (Test-Path -LiteralPath $embedded)){
        $hash=(Get-FileHash -LiteralPath $embedded).Hash
        $candidates=@($candidates|Where-Object {(Get-FileHash -LiteralPath (Join-Path $_.FullName $leaf)).Hash -eq $hash})
    }
    foreach($candidate in $candidates){
        $elf=@(Get-ChildItem -LiteralPath $candidate.FullName -Recurse -File -Filter '*.so*' | Where-Object {$_.Name -match '\.so(?:\.[0-9]+)*$'})
        $companions+=[pscustomobject]@{ref=$ref;package=$candidate.Name;linuxFiles=@($elf | Select-Object -ExpandProperty Name)}
        if($elf.Count){
            if($candidates.Count -ne 1){throw "Ambiguous Linux companion package for $ref"}
            $packages[$candidate.Name]=$candidate.FullName
        }
    }
    if(!$candidates.Count){$companions+=[pscustomobject]@{ref=$ref;package=$null;embedded=(Test-Path -LiteralPath $embedded);linuxFiles=@()}}
}
foreach($p in $packages.Values){
    if((Get-Item -LiteralPath $p).Attributes.HasFlag([IO.FileAttributes]::ReparsePoint)){throw "Unexpected package reparse point: $p"}
}
$elfFiles=@(foreach($p in $packages.Values){Get-ChildItem -LiteralPath $p -Recurse -File -Filter '*.so*' | Where-Object {$_.Name -match '\.so(?:\.[0-9]+)*$'}|Select-Object -ExpandProperty FullName})
$umd=[bool](@($values['UserModeDriverNameWsl'])|Where-Object {$_ -and (Test-Path -LiteralPath $_ -PathType Leaf)})
$notes=@()
if($Card.Pnp -like '*VEN_10DE&DEV_1F15*' -and $Card.Driver -eq '32.0.16.1742'){
    $notes+='本机 RTX 2060 在 Debian 12 双卡来宾通过 CUDA 和 D3D12 数值验证。NVML 仍可能产生 dxgkio_escape -22。参见 artifacts/reports/phase1/results.md。'
}
if($Card.Pnp -like '*VEN_8086*'){
    if(!$umd){$notes+='缺少已注册且存在的 Intel WSL 用户态驱动。请核对显示驱动版本及伴随 INF 包。'}
    else{$notes+='来宾使用 gpupv-guest verify 测试 D3D12 Compute。有 GPU OpenCL ICD 时会加验 OpenCL；可选视频使用 --with-video。'}
    if($Card.Driver -eq '32.0.101.6876' -and $Card.Pnp -like '*DEV_9A49*'){
        $notes+='本机 Debian 12 来宾的 Iris Xe 验证了 D3D12 的 64 项和 OpenCL 的 32 项计算结果。单独运行 Intel OpenCL 时仍有两条 dxgkio_reserve_gpu_va -75，详见 artifacts/reports/phase1/compute-isolated/opencl.dmesg。'
        if($reg.GetValueNames() -notcontains 'DXCoreWSLAttributes'){
            $notes+='适配器键缺少 DXCoreWSLAttributes。实测 DXCore 对此值的查询由宿主返回 0xc0000034，旧版 DX9/10/11 UMD 名称查询返回 0xc000000d。同一进程随后成功创建 D3D12 设备并完成 64 项计算回读。'
        }
    }
}
[pscustomobject]@{name=$Card.Name;version=$Card.Driver;inf=$inf;primary=$primary.Name;packages=@($packages.Values|Sort-Object);registry=$values;companions=$companions;linuxFiles=$elfFiles;wslUmdPresent=$umd;notes=$notes}
