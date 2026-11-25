# Run one authenticated, disposable ARM64 Hyper-V guest and save per-stage evidence.
param([Parameter(Mandatory)][ValidatePattern('^[a-z0-9.-]+$')][string]$Target,
    [Parameter(Mandatory)][string]$ImageRecord,[Parameter(Mandatory)][string]$QemuImg,
    [Parameter(Mandatory)][string]$Key,[Parameter(Mandatory)][string]$Iso,
    [guid]$ResumeId,[switch]$ExHyperVMmio,[int]$MemoryMiB=1792,[switch]$KeepOnFailure,[switch]$IsolateAzureStockModule,[switch]$ThinPrebuilt,[switch]$InitialFirmwareProbeOnly)
$ErrorActionPreference='Stop'
$root=Split-Path $PSScriptRoot
$img=Get-Content -LiteralPath $ImageRecord -Raw | ConvertFrom-Json
$isoPath=(Resolve-Path -LiteralPath $Iso).Path
$record=New-Item -Type Directory -Force "$root/artifacts/reports/arm64-expanded/$Target"
$img | Select-Object Arch,Source,ChecksumSource,PublishedDigest,OriginalSha256,Sha256 | ConvertTo-Json | Set-Content "$record/image.json"
if($ResumeId){$vm=Get-VM -Id $ResumeId}else{
    $gpu=@(Get-VMHostPartitionableGpu | Where-Object Name -like '*VEN_QCOM*')
    if($gpu.Count -ne 1){throw 'Expected one partitionable Qualcomm GPU'}
    $made=& "$PSScriptRoot/New-TestVM.ps1" -Image $img.Image -Sha256 $img.Sha256 -PublicKey "$Key.pub" -QemuImg $QemuImg -GpuPath $gpu[0].Name -SecureBoot -DeploymentIso $isoPath -ExHyperVMmio:$ExHyperVMmio -NoCheckpoint -MemoryMiB $MemoryMiB -UseDifferencingDisk:($img.UseDifferencingDisk -eq $true) | Where-Object Id
    $vm=Get-VM -Id $made.Id
}
$dir=Join-Path $root ".test/$($vm.Name)"
if($vm.Name -notmatch '^gpupv-test-[a-f0-9]{32}$' -or (Get-Content "$dir/vm-id.txt") -ne $vm.Id){throw 'Invalid VM ownership record'}
if(!(Get-VMDvdDrive -VM $vm | Where-Object Path -eq $isoPath)){throw 'Wrong optical media'}
$ssh=@('-i',$Key,'-o','BatchMode=yes','-o','ConnectTimeout=3','-o','ServerAliveInterval=8','-o','ServerAliveCountMax=2','-o','StrictHostKeyChecking=accept-new','-o',"HostKeyAlias=$($vm.Id)",'-o',"UserKnownHostsFile=$dir/known_hosts")
$state=[ordered]@{target=$Target;vm=$vm.Name;vmId=$vm.Id.ToString();started=(Get-Date).ToString('o');mediaSha256=(Get-FileHash -LiteralPath $isoPath).Hash.ToLowerInvariant();secureBoot=$null;route=$null;kernel=$null;compute=$false;clean=$false;errors=@();diagnostics=@();stage='boot'}
function Save-State {$state|ConvertTo-Json -Depth 5|Set-Content "$record/result.json"}
function Save-BootScreen([string]$Name){
    try{
        $ns='root/virtualization/v2'
        $system=Get-CimInstance -Namespace $ns -ClassName Msvm_ComputerSystem -Filter "Name='$($vm.Id)'"
        $settings=Get-CimAssociatedInstance -InputObject $system -Association Msvm_SettingsDefineState -ResultClassName Msvm_VirtualSystemSettingData
        $service=Get-CimInstance -Namespace $ns -ClassName Msvm_VirtualSystemManagementService
        $frame=Invoke-CimMethod -InputObject $service -MethodName GetVirtualSystemThumbnailImage -Arguments @{TargetSystem=$settings;WidthPixels=[uint16]800;HeightPixels=[uint16]600}
        if($frame.ReturnValue -or $frame.ImageData.Length -lt 960000){return}
        Add-Type -AssemblyName System.Drawing
        $format=[Drawing.Imaging.PixelFormat]::Format16bppRgb565
        $bmp=[Drawing.Bitmap]::new(800,600,$format)
        try{
            $bits=$bmp.LockBits([Drawing.Rectangle]::new(0,0,800,600),[Drawing.Imaging.ImageLockMode]::WriteOnly,$format)
            try{[Runtime.InteropServices.Marshal]::Copy($frame.ImageData,$frame.ImageData.Length-960000,$bits.Scan0,960000)}finally{$bmp.UnlockBits($bits)}
            $bmp.Save("$record/$Name.png",[Drawing.Imaging.ImageFormat]::Png)
        }finally{$bmp.Dispose()}
    }catch{Write-Warning "Cannot capture boot screen: $_"}
}
function Connect-Test([string]$OldBoot='', [int]$Seconds=85){
    $deadline=(Get-Date).AddSeconds($Seconds)
    $mac=(Get-VMNetworkAdapter -VM $vm).MacAddress
    do{
        $ips=@((Get-VMNetworkAdapter -VM $vm).IPAddresses | Where-Object {$_ -match '^\d+\.'})
        $ips+=@(Resolve-DnsName "$($vm.Name).mshome.net" -Type A -QuickTimeout -ErrorAction SilentlyContinue | Where-Object IPAddress | Select-Object -ExpandProperty IPAddress)
        $ips+=@(Get-NetNeighbor -AddressFamily IPv4 | Where-Object {($_.LinkLayerAddress -replace '-','') -eq $mac} | Select-Object -ExpandProperty IPAddress)
        foreach($ip in @($ips | Where-Object {$_} | Select-Object -Unique)){
            $id=& ssh.exe -n @ssh "tester@$ip" 'hostname -s; cat /proc/sys/kernel/random/boot_id' 2>$null
            if(!$LASTEXITCODE -and $id.Count -eq 2 -and $id[0] -eq $vm.Name -and $id[1] -match '^[a-f0-9-]{36}$' -and $id[1] -ne $OldBoot){
                $script:remote="tester@$ip";$script:boot=$id[1];return
            }
        }
        Start-Sleep 2
    }while((Get-Date) -lt $deadline)
    throw "Guest identity or new boot ID unavailable after $Seconds seconds"
}
function Remote([string]$Step,[string]$Command){
    $state.stage=$Step;Save-State
    $output=& ssh.exe -n @ssh $remote $Command 2>&1
    $exit=$LASTEXITCODE
    $output | Out-File "$record/$Step.txt" -Encoding utf8
    if($exit){throw "$Step exited $exit"}
    $output
}
function Reboot-Test([string]$Step){
    $before=$boot
    $null=Remote "$Step-request" 'sudo -n sh -c ''nohup sh -c "sleep 2; /sbin/reboot" </dev/null >/dev/null 2>&1 &''
'
    Connect-Test $before 120
    @($before,$boot) | Set-Content "$record/$Step-ids.txt"
}
function Firmware([bool]$Enabled){
    if((Get-VM -Id $vm.Id).State -ne 'Off'){Stop-VM -VM $vm -TurnOff -Force}
    $mode=if($Enabled){'On'}else{'Off'}
    Set-VMFirmware -VM $vm -EnableSecureBoot $mode -SecureBootTemplate MicrosoftUEFICertificateAuthority
    & "$PSScriptRoot/Start-TestVM.ps1" -Id $vm.Id
}
try{
    Save-State
    Copy-Item "$dir/mmio-*.json" -Destination $record.FullName
    try{Connect-Test '' 200}catch{
        Save-BootScreen 'initial-secure-boot'
        $_.Exception.Message | Set-Content "$record/secure-boot-first-attempt.txt"
        Firmware $false
        Connect-Test '' 120
    }
    if($Target -eq 'devuan'){
        $installed=$ResumeId -and (Remote current-os '. /etc/os-release; echo "$ID"') -contains 'devuan'
        if(!$installed){
            & scp.exe @ssh "$PSScriptRoot/prepare-devuan-installer" "${remote}:"
            if($LASTEXITCODE){throw 'Could not stage Devuan netboot'}
            $null=Remote devuan-netboot 'sudo -n timeout 480 sh /home/tester/prepare-devuan-installer'
            $before=$boot
            $null=Remote installer-start 'sudo -n sh -c ''nohup sh -c "sleep 2; /sbin/reboot" </dev/null >/dev/null 2>&1 &'''
            Connect-Test $before 1100
        }
        $null=Remote clock "sudo -n date -u -s @$([DateTimeOffset]::UtcNow.ToUnixTimeSeconds())"
        $null=Remote devuan-identity 'set -eu; . /etc/os-release; test "$ID" = devuan; test "$(cat /proc/1/comm)" != systemd; cat /etc/os-release /proc/1/comm'
    }
    $cmd='sh /home/tester/arm64-regression-guest'
    & scp.exe @ssh "$PSScriptRoot/arm64-regression-guest" "$PSScriptRoot/prepare-test-mok" "$PSScriptRoot/leap-module-policy" "$PSScriptRoot/prepare-leap-kernel" "${remote}:"
    if($LASTEXITCODE){throw 'Cannot copy guest test helpers'}
    $null=Remote prepare "sudo -n timeout 720 $cmd prepare $Target"
    if((Get-VMFirmware -VM $vm).SecureBoot -eq 'Off' -and !$InitialFirmwareProbeOnly){
        $firmware=Remote firmware-packages "sudo -n timeout 480 $cmd firmware $Target"
        if($firmware -contains 'retry_secure_boot'){
            Firmware $true
            try{Connect-Test '' 150}catch{
                Save-BootScreen 'updated-secure-boot'
                $_.Exception.Message | Set-Content "$record/secure-boot-after-update.txt"
                Firmware $false;Connect-Test '' 200
            }
        }else{
            'No ARM64 shim or MOK manager found on the guest EFI filesystem after the initial secure boot attempt.' | Set-Content "$record/secure-boot-after-update.txt"
        }
    }
    if($Target -match '-hwe$|-ga-current$|^debian-(12-backports|sid|testing)$|^kali$|^suse-'){Reboot-Test kernel-boot}
    $transport=Remote transport "sudo -n timeout 480 $cmd transport $Target"
    $state.kernel=[string](Remote kernel 'uname -r' | Select-Object -Last 1)
    $state.route=if($transport -contains 'install_route=prebuilt'){'prebuilt'}else{'source'}
    if($ThinPrebuilt -and $state.route -eq 'prebuilt'){$null=Remote thin-prebuilt "sudo -n $cmd thin-prebuilt $Target"}
    if($state.route -eq 'source'){
        try{$null=Remote build-deps "sudo -n timeout 600 $cmd build-deps $Target"}catch{
            $previous=$state.kernel
            $null=Remote update-kernel "sudo -n timeout 600 $cmd update-kernel $Target"
            Reboot-Test updated-kernel
            $state.kernel=[string](Remote updated-release 'uname -r' | Select-Object -Last 1)
            if($state.kernel -eq $previous){throw "No matching headers for $previous and kernel update retained the same release"}
            $transport=Remote updated-transport "sudo -n timeout 480 $cmd transport $Target"
            $state.route=if($transport -contains 'install_route=prebuilt'){'prebuilt'}else{'source'}
            if($state.route -eq 'source'){$null=Remote updated-build-deps "sudo -n timeout 600 $cmd build-deps $Target"}
        }
    }
    $envInfo=Remote environment "sudo -n $cmd environment $Target"
    $state.secureBoot=($envInfo -contains 'SecureBoot enabled')
    if($state.secureBoot){
        $pass=[guid]::NewGuid().ToString('N').Substring(0,12)
        $state.stage='mok';Save-State
        $before=$boot
        $msg=$pass | ssh.exe @ssh $remote 'sudo -n python3 /home/tester/prepare-test-mok /mnt/gpupv/guest/gpupv-guest' 2>&1
        $rc=$LASTEXITCODE;$msg | Out-File "$record/mok-request.txt"
        if($rc){throw "MOK request exited $rc"}
        if($msg -contains 'enrollment_requested'){
            & "$PSScriptRoot/Confirm-TestMok.ps1" -Id $vm.Id -Password $pass | Out-File "$record/shim-menus.txt"
            Connect-Test $before 120
        }
    }
    if($IsolateAzureStockModule){
        $null=Remote azure-stock "sudo -n $cmd azure-stock $Target"
        $null=Remote azure-isolate "sudo -n timeout 480 $cmd azure-isolate $Target"
    }
    $null=Remote install "sudo -n timeout 600 $cmd install $Target"
    Reboot-Test installed-boot
    $null=Remote trust "sudo -n $cmd trust $Target"
    $mark='gpupv-sample-'+[guid]::NewGuid().ToString('N')
    $null=Remote marker "echo $mark | sudo -n tee /dev/kmsg"
    $workloadError=$null
    try{
        $sample=Remote workload "$cmd sample $Target"
        if(!($sample -match '^Adapter 4d4f4351:36333630 hardware=1$') -or !($sample -match 'matched=64/64') -or !($sample -match 'Verified hardware adapters=1')){throw 'Incomplete Adreno numerical result'}
        $state.compute=$true
    }catch{$workloadError=$_.Exception.Message}
    $dmesg=Remote dmesg "sudo -n dmesg | sed -n '/$mark/,$ p'"
    if(!($dmesg -match $mark)){throw 'Missing kernel sample boundary'}
    $state.diagnostics=@($dmesg | Select-String -Pattern 'Ioctl failed: (-[0-9]+)' | ForEach-Object {$_.Matches[0].Groups[1].Value})
    if($workloadError){
        $null=Remote loader-diagnostics 'for f in /usr/lib/wsl/drivers/*/*.so; do [ -f "$f" ] || continue; echo "$f"; LD_LIBRARY_PATH=/usr/lib/wsl/lib ldd "$f" 2>&1 | grep "not found" || true; done'
        $state.errors+=("workload: "+$workloadError)
    }
    if($Target -eq 'mmio-trace'){
        $tr=Remote traced-workload "$cmd trace $Target"
        if(!($tr -match 'matched=64/64')){throw 'Traced workload failed'}
        & scp.exe @ssh "${remote}:/tmp/gpupv-files.trace" "$record/strace-file.txt"
        if($LASTEXITCODE){throw 'Could not retrieve file trace'}
        $null=Remote traced-tree 'find -L /usr/lib/wsl -type f -exec file {} +'
    }
    $null=Remote uninstall 'sudo -n /usr/local/bin/gpupv-guest uninstall'
    Reboot-Test uninstalled-boot
    $null=Remote cleanup "sudo -n $cmd clean $Target"
    if($IsolateAzureStockModule){$null=Remote azure-restore "sudo -n $cmd azure-restore $Target"}
    $state.clean=$true;$state.stage=if($state.compute){'finished'}else{'workload'}
}catch{
    if($state.stage -in @('boot','mok')){Save-BootScreen "$($state.stage)-failure"}
    $state.errors+=($_.Exception.Message)
    Write-Output "$Target $($state.stage) $($_.Exception.Message)"
    if($remote){
        & ssh.exe -n @ssh $remote 'uname -a; sudo -n dmesg | tail -160; ls -l /dev/dxg; df -h /' 2>&1 |
            Out-File "$record/failure-diagnostics.txt"
    }
}
finally{
    $state.finished=(Get-Date).ToString('o');Save-State
    if(!$KeepOnFailure -or !$state.errors.Count){
        if((Get-VM -Id $vm.Id).State -ne 'Off'){Stop-VM -VM $vm -Force -TurnOff}
        & "$PSScriptRoot/Remove-TestVM.ps1" -Id $vm.Id | Out-File "$record/host-cleanup.txt"
    }
}
