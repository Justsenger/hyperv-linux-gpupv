#requires -Version 7.4
[CmdletBinding(PositionalBinding=$false)]
param([Parameter(Position=0)][ValidateSet('list','doctor','pack','iso','push','fetch-wsl-libs')]$Command='list',[string[]]$Gpu,[string]$Bundle,
      [ValidateSet('x86_64','aarch64')][string]$Arch,[string]$Output,[string]$Destination,[string]$VMName,
      [Alias('wsl-lib-dir','-wsl-lib-dir')][string]$WslLibDir,[string]$IdentityFile,[string]$KnownHostsFile,[string]$HostKeyAlias,[Parameter(ValueFromRemainingArguments=$true)][string[]]$Trailing)
$ErrorActionPreference='Stop'
# In an interactive PowerShell call a GNU-style double dash can be a positional string.
$positional=@('Gpu','Arch','Output','Destination','IdentityFile','KnownHostsFile','HostKeyAlias') | Where-Object {-not $PSBoundParameters.ContainsKey($_)}
$position=0
for($index=0;$index -lt $Trailing.Count;$index++){
    $value=$Trailing[$index]
    if($value -eq '--wsl-lib-dir'){
        if($WslLibDir -or ++$index -ge $Trailing.Count){throw 'Expected one directory after --wsl-lib-dir'}
        $WslLibDir=$Trailing[$index]
    }elseif($value.StartsWith('-') -or $position -ge @($positional).Count){
        throw "Unexpected argument $value"
    }else{
        Set-Variable -Name @($positional)[$position++] -Value $value
    }
}
. "$PSScriptRoot/BundleTools.ps1"
$repo=Split-Path $PSScriptRoot
$required='libd3d12.so','libd3d12core.so','libdxcore.so'
function Get-Gpus {
    $display=Get-CimInstance Win32_PnPSignedDriver -Filter "DeviceClass='DISPLAY'"
    foreach ($adapter in Get-VMHostPartitionableGpu) {
        $match=@($display | Where-Object {
            $_.DeviceID -and $adapter.Name.StartsWith(('\\?\'+$_.DeviceID.Replace('\','#')+'#'),[StringComparison]::OrdinalIgnoreCase)
        })
        if($match.Count -ne 1){throw "Cannot identify the bound display INF for $($adapter.Name)"}
        [pscustomobject]@{Name=$match[0].DeviceName;Instance=$adapter.Name;Inf=$match[0].InfName;Driver=$match[0].DriverVersion;Pnp=$match[0].DeviceID}
    }
}
function Test-Elf($File) {
    if(-not [IO.File]::Exists($File)){return $false}
    $b=New-Object byte[] 64
    $s=[IO.File]::OpenRead($File)
    try{$n=$s.Read($b,0,64)}finally{$s.Dispose()}
    $machine=if($Arch -eq 'aarch64'){183}else{62}
    return ($n -eq 64 -and [BitConverter]::ToString($b,0,6) -eq '7F-45-4C-46-02-01' -and [BitConverter]::ToUInt16($b,16) -eq 3 -and [BitConverter]::ToUInt16($b,18) -eq $machine)
}
$native=[Runtime.InteropServices.RuntimeInformation]::OSArchitecture.ToString()
$nativeArch=@{X64='x86_64';Arm64='aarch64'}[$native]
if(!$nativeArch){throw "当前宿主架构 $native 缺少实现。"}
if(!$Arch){$Arch=$nativeArch}
$manifest=Get-Content -LiteralPath "$PSScriptRoot/wsl-runtime.json" -Raw | ConvertFrom-Json
$files=@($manifest.files | Where-Object arch -eq $Arch)
if($files.Count -ne $required.Count -or (Compare-Object $required @($files.name))){throw 'Incomplete runtime manifest'}
$cache=Join-Path $repo ".tools/wsl-runtime/$($manifest.commit)/$Arch"
function Assert-Cache($dir){
    foreach($entry in $files){
        $path=Join-Path $dir $entry.name
        if(!(Test-Elf $path) -or (Get-FileHash -LiteralPath $path).Hash -ne $entry.sha256){throw "Runtime verification failed: $path"}
    }
}
if($Command -eq 'fetch-wsl-libs'){
    if(!(Test-Path -LiteralPath $cache)){
        $parent=[IO.Directory]::CreateDirectory((Split-Path $cache))
        $stage=$parent.CreateSubdirectory([guid]::NewGuid().ToString('N')).FullName
        try{
            foreach($entry in $files){
                $url="https://raw.githubusercontent.com/SherryPlatform/Microsoft.DirectX.Linux.Binaries/$($manifest.commit)/$($entry.path)"
                Invoke-WebRequest -Uri $url -OutFile (Join-Path $stage $entry.name)
            }
            Assert-Cache $stage
            try{[IO.Directory]::Move($stage,$cache)}catch{if(!(Test-Path -LiteralPath $cache)){throw}}
        }finally{
            if((Split-Path $stage) -eq $parent.FullName -and (Split-Path -Leaf $stage) -match '^[0-9a-f]{32}$' -and (Test-Path -LiteralPath $stage)){Remove-Item -LiteralPath $stage -Force -Recurse}
        }
    }
    Assert-Cache $cache
    Get-ChildItem -LiteralPath $cache -File | Get-FileHash
    return
}
if(!(Get-Command Get-VMHostPartitionableGpu -ErrorAction SilentlyContinue)){
    throw '未检测到可用的 Hyper-V 管理模块。请先启用 Hyper-V 及其 PowerShell 管理工具。'
}
$cards=@(Get-Gpus)
if($Command -eq 'list'){$cards;return}
if(!$cards.Count){throw 'Hyper-V 没有列出可分区显卡。请检查显卡驱动和 GPU-PV 支持。'}
if($nativeArch -ne $Arch){throw "宿主架构 $native 与目标 $Arch 不匹配，请选择相同架构。"}
$roots=@("$env:ProgramFiles\WSL\lib","$env:SystemRoot\System32\lxss\lib")
if($WslLibDir){
    $specified=$ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($WslLibDir)
    if([IO.Path]::TrimEndingDirectorySeparator($specified) -eq $cache){Assert-Cache $cache}
    $roots+=$specified
}
$libs=@{}
foreach($n in $required){
    foreach($root in $roots){
        $f=Join-Path $root $n
        if(Test-Elf $f){$libs[$n]=$f;break}
    }
}
$missing=@($required | Where-Object {-not $libs.ContainsKey($_)})
if(!$Bundle -and $missing -and (Test-Path -LiteralPath $cache)){
    Assert-Cache $cache
    foreach($n in $missing){$libs[$n]=Join-Path $cache $n}
    $missing=@()
}
if($missing -and !$Bundle){throw "缺少匹配 $Arch 的 WSL 运行库：$($missing -join ', ')。请指定 --wsl-lib-dir 或运行 fetch-wsl-libs。已检查 $($roots -join ' 和 ')。"}
$store=(Get-Item "$env:SystemRoot\System32\DriverStore\FileRepository").FullName
if($Command -eq 'doctor'){
    if($Bundle){
        $zip=[IO.Compression.ZipFile]::OpenRead((Resolve-Path -LiteralPath $Bundle).Path)
        try{$libs['bundle']=Read-BundleMetadata $zip $nativeArch $files}finally{$zip.Dispose()}
    }
    $selected=if($Gpu){@(Get-SelectedGpu $cards $Gpu)}else{$cards}
    if(!$selected){throw 'Unknown adapter'}
    $libs['adapters']=@(foreach($c in $selected){& "$PSScriptRoot/Get-GpuRuntime.ps1" -Card $c -Store $store})
    $libs;return
}
if(!$Gpu){throw '请指定一个或多个 -Gpu 实例路径或完整名称。'}
$selected=@(Get-SelectedGpu $cards $Gpu)
if($VMName){
    if($Command -ne 'iso' -or [Management.Automation.WildcardPattern]::ContainsWildcardCharacters($VMName)){throw 'Specify an exact VM name with iso'}
    $vm=Get-VM -Name $VMName -ErrorAction Stop
    $adapters=@(Get-VMGpuPartitionAdapter -VM $vm)
    if(!$adapters -or (Compare-Object @($adapters.InstancePath) @($selected.Instance))){throw 'VM partitions differ from selected GPUs'}
}
if($Command -ne 'push' -and (!$Output -or (Test-Path -LiteralPath $Output))){throw 'Specify a new -Output filename'}
if($Command -eq 'push' -and $Destination -notmatch '^[a-zA-Z0-9_][a-zA-Z0-9_.-]*@[a-zA-Z0-9][a-zA-Z0-9.:-]*$'){throw 'Expected -Destination user@host'}
$tmpRoot=(Get-Item -LiteralPath ([IO.Path]::GetTempPath())).FullName
$stage=[IO.Directory]::CreateTempSubdirectory('gpupv-').FullName
try {
    $payload=New-Item -ItemType Directory "$stage/payload"
    if($Bundle){
        $zip=[IO.Compression.ZipFile]::OpenRead((Resolve-Path -LiteralPath $Bundle).Path)
        try{
            $bundleMeta=Read-BundleMetadata $zip $nativeArch $files
            if($zip.Entries | Where-Object {$_.FullName -match '^(drivers/|device\.json$)|[:\\]|(^|/)\.\.(/|$)'}){throw 'Invalid bundle paths'}
            [IO.Compression.ZipFileExtensions]::ExtractToDirectory($zip,$payload.FullName)
        }finally{$zip.Dispose()}
        foreach($entry in $files){
            $p=Join-Path "$payload/lib" $entry.name
            if(!(Test-Elf $p) -or (Get-FileHash -LiteralPath $p).Hash -ne $entry.sha256 -or $bundleMeta.libraries.($entry.name) -ne $entry.sha256){throw "Invalid bundled runtime: $p"}
        }
        if((Get-FileHash -LiteralPath "$payload/guest/d3d12-compute").Hash -ne $bundleMeta.probeSha256){throw 'Invalid probe checksum'}
    }else{
        New-Item -ItemType Directory "$payload/lib"|Out-Null
        foreach($n in $required){Copy-Item -LiteralPath $libs[$n] -Destination "$payload/lib/$n"}
        Copy-Item -Recurse -LiteralPath "$repo/kernel","$repo/guest" -Destination $payload
        Copy-Item -LiteralPath "$repo/LICENSE" -Destination $payload
    }
    New-Item -ItemType Directory "$payload/drivers"|Out-Null
    $devices=@(foreach($card in $selected){
        $runtime=& "$PSScriptRoot/Get-GpuRuntime.ps1" -Card $card -Store $store
        if(!$runtime.linuxFiles){throw "No Linux UMD in $($card.Name)"}
        $claimed=@{}
        foreach($file in $runtime.linuxFiles){
            if(!(Test-Elf $file)){throw "UMD architecture mismatch: $file"}
        }
        foreach($path in $runtime.packages){
            $dst=Join-Path "$payload/drivers" (Split-Path -Leaf $path)
            if(!(Test-Path -LiteralPath $dst)){Copy-Item -Recurse -LiteralPath $path -Destination $dst}
            foreach($inf in Get-ChildItem -LiteralPath $path -File -Filter '*.inf'){
                $aliases=& "$PSScriptRoot/Get-WslFileMap.ps1" -Inf $inf.FullName -Arch $Arch
                foreach($entry in $aliases.GetEnumerator()){
                    $source=Join-Path $path $entry.Value
                    if($entry.Key -match '\.so(?:\.\d+)*$' -and !(Test-Elf $source)){throw "Wrong ELF: $source"}
                    $claimed[$entry.Key]=$true
                    Add-DriverFile $source "$payload/lib" $entry.Key
                }
            }
        }
        foreach($file in $runtime.linuxFiles){
            $leaf=Split-Path -Leaf $file
            if(!$claimed.ContainsKey($leaf)){Add-DriverFile $file "$payload/lib" $leaf}
        }
        @{name=$card.Name;device=$card.Pnp;version=$card.Driver;package=$runtime.primary}
    })
    @{schemaVersion=1;arch=$Arch;adapters=$devices} | ConvertTo-Json -Depth 4 | Set-Content "$payload/device.json" -Encoding utf8NoBOM
    if($Command -eq 'iso'){
        & "$PSScriptRoot/New-GpuPvIso.ps1" -Source $payload -Output $Output
        if($VMName){
            $iso=(Resolve-Path -LiteralPath $Output).Path
            Add-VMDvdDrive -VM $vm -Path $iso -ErrorAction Stop
            Get-VMDvdDrive -VM $vm | Where-Object Path -eq $iso
        }
        return
    }
    $bundle="$stage/gpupv.tar"
    tar.exe -cf $bundle -C $payload .
    if($LASTEXITCODE){throw 'Archive failed'}
    if($Command -eq 'pack'){
        $dest=$ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($Output)
        $partial="$dest.$([guid]::NewGuid()).part"
        try{
            [IO.File]::Copy($bundle,$partial)
            [IO.File]::Move($partial,$dest)
        }finally{if(Test-Path -LiteralPath $partial){Remove-Item -LiteralPath $partial}}
        return
    }
    $remote='set -eu; d=$(mktemp -d "$HOME/gpupv-deploy.XXXXXXXX"); trap ''rm -rf "$d"'' EXIT; tar -xf - -C "$d"; sudo -n sh "$d/guest/setup"; /usr/local/bin/gpupv-guest check'
    $p=[Diagnostics.ProcessStartInfo]::new('ssh.exe')
    $p.UseShellExecute=$false
    $p.RedirectStandardInput=$true
    $p.RedirectStandardOutput=$true
    $p.RedirectStandardError=$true
    $options=@('-o','BatchMode=yes')
    if($IdentityFile){$options+=@('-i',(Resolve-Path -LiteralPath $IdentityFile).Path)}
    if($KnownHostsFile){$options+=@('-o',('UserKnownHostsFile='+(Resolve-Path -LiteralPath $KnownHostsFile).Path),'-o','StrictHostKeyChecking=yes')}
    if($HostKeyAlias){
        if($HostKeyAlias -notmatch '^[a-zA-Z0-9.-]+$'){throw 'Invalid SSH host key alias'}
        $options+=@('-o',"HostKeyAlias=$HostKeyAlias")
    }
    foreach($arg in ($options+@('--',$Destination,$remote))){$p.ArgumentList.Add($arg)}
    $ssh=[Diagnostics.Process]::Start($p)
    $stdout=$ssh.StandardOutput.ReadToEndAsync()
    $stderr=$ssh.StandardError.ReadToEndAsync()
    $stream=[IO.File]::OpenRead($bundle)
    try{$stream.CopyTo($ssh.StandardInput.BaseStream)}finally{$stream.Dispose();$ssh.StandardInput.Close();$ssh.WaitForExit()}
    $stdout.GetAwaiter().GetResult()
    $stderr.GetAwaiter().GetResult()
    if($ssh.ExitCode){throw "SSH deployment failed ($($ssh.ExitCode))"}
} finally {
    $actual=(Resolve-Path -LiteralPath $stage).Path
    if([IO.Path]::GetDirectoryName($actual) -eq $tmpRoot.TrimEnd('\') -and [IO.Path]::GetFileName($actual) -like 'gpupv-*'){Remove-Item -LiteralPath $actual -Recurse -Force}
}





