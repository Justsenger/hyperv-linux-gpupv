param([Parameter(Mandatory)][string[]]$Target,[Parameter(Mandatory)][string]$QemuImg,
      [Parameter(Mandatory)][string]$Key,[Parameter(Mandatory)][string]$NvidiaIso,
      [Parameter(Mandatory)][string]$IntelIso,[ValidateSet('NVIDIA','Intel')][string[]]$VendorNames=@('NVIDIA','Intel'),[int]$MemoryMiB=1024,[string]$ImageManifestDir,[switch]$SshPush)
$ErrorActionPreference='Stop'
$root=Split-Path $PSScriptRoot
$runtime=[ordered]@{
    NVIDIA=@{iso=(Resolve-Path $NvidiaIso).Path;vendor='VEN_10DE'}
    Intel=@{iso=(Resolve-Path $IntelIso).Path;vendor='VEN_8086'}
}
$proxy=''
if($env:HTTPS_PROXY){
    $uri=[uri]$env:HTTPS_PROXY
    if(!$uri.UserInfo -and $uri.Authority -match '^[a-zA-Z0-9.:-]+$' -and $uri.Scheme -in 'http','https'){
        $proxy=$uri.GetLeftPart([UriPartial]::Authority)
    }
}
function Connect-Guest($vm,$ssh){
    $until=(Get-Date).AddMinutes(4)
    do{
        $mac=(Get-VMNetworkAdapter -VM $vm).MacAddress
        $ips=@(Get-NetNeighbor -AddressFamily IPv4 | Where-Object {($_.LinkLayerAddress -replace '-','') -eq $mac} | Select-Object -ExpandProperty IPAddress)
        $ips+=@(Resolve-DnsName "$($vm.Name).mshome.net" -Type A -ErrorAction SilentlyContinue | Where-Object IPAddress | Select-Object -ExpandProperty IPAddress)
        foreach($ip in ($ips|Select-Object -Unique)){
            $name=& ssh.exe @ssh "tester@$ip" 'cat /proc/sys/kernel/hostname' 2>$null
            if($LASTEXITCODE -eq 0 -and $name -eq $vm.Name){return $ip}
        }
        Start-Sleep 3
    }while((Get-Date) -lt $until)
    throw "No authenticated guest for $($vm.Name)"
}
foreach($base in $Target){
    if($ImageManifestDir){
        $image=Get-Content -LiteralPath (Join-Path $ImageManifestDir "e2e-image-$base.json") -Raw | ConvertFrom-Json
        $images=(Resolve-Path "$root/.test/images").Path
        if((Split-Path (Resolve-Path -LiteralPath $image.Image).Path) -ne $images -or $image.Sha256 -notmatch '^[a-f0-9]{64}$'){throw "Invalid image record for $base"}
    }else{$image=& "$PSScriptRoot/Get-CloudImage.ps1" -Target $base}
    foreach($vendor in $VendorNames){
        # Let an operator drain a matrix before changing its deployment media.
        # Each live guest finishes its workload, recovery and cleanup first.
        if($ImageManifestDir -and (Test-Path -LiteralPath (Join-Path $ImageManifestDir 'gpupv-test.stop'))){
            Write-Output "Matrix drained before $base / $vendor"
            return
        }
        $gpu=@(Get-VMHostPartitionableGpu | Where-Object Name -like "*$($runtime[$vendor].vendor)*")
        if($gpu.Count -ne 1){throw "Ambiguous GPU $vendor"}
        $media=if(!$SshPush){$runtime[$vendor].iso}
        $created=& "$PSScriptRoot/New-TestVM.ps1" -Image $image.Image -Sha256 $image.Sha256 -QemuImg $QemuImg -PublicKey "$Key.pub" -MemoryMiB $MemoryMiB -GpuPath $gpu[0].Name -SecureBoot:($base -ne 'arch') -NoCheckpoint -DeploymentIso $media | Where-Object Id
        $vm=Get-VM -Id $created.Id
        $dir=Join-Path $root ".test/$($vm.Name)"
        if($vm.Name -notmatch '^gpupv-test-[a-f0-9]{32}$' -or (Get-Content "$dir/vm-id.txt") -ne $vm.Id){throw 'Ownership mismatch'}
        $log=New-Item -Type Directory "$root/artifacts/reports/e2e-$base-$vendor-$($vm.Name.Substring(11,8))"
        $ip=$null
        $ssh=@('-i',$Key,'-o','BatchMode=yes','-o','ConnectTimeout=4','-o','StrictHostKeyChecking=accept-new','-o',"HostKeyAlias=$($vm.Id)",'-o',"UserKnownHostsFile=$dir/known_hosts")
        try{
            $ip=Connect-Guest $vm $ssh
            if($base -like 'ubuntu-*'){
                $mirror='set -eu; sudo -n cloud-init status --wait || test "$?" -eq 2; for f in /etc/apt/sources.list /etc/apt/sources.list.d/ubuntu.sources; do if test -f "$f"; then sudo -n sed -i -E "s@https?://(archive|security).ubuntu.com/ubuntu@https://mirrors.ustc.edu.cn/ubuntu@g" "$f"; fi; done'
                & ssh.exe @ssh "tester@$ip" $mirror *> "$log/ubuntu-mirror.txt"
                if($LASTEXITCODE){throw 'Cannot prepare signed Ubuntu mirror'}
            }
            $prepare=switch -Regex ($base){
                '^(ubuntu|debian)' {'apt-get update && apt-get install -y --no-install-recommends gcc g++ mokutil openssl make libc6-dev linux-headers-$(uname -r) kmod && (apt-get install -y --no-install-recommends ffmpeg mesa-va-drivers vainfo clinfo || true)'}
                '^fedora' {'dnf -y --setopt=install_weak_deps=False install gcc gcc-c++ mokutil openssl make elfutils-libelf-devel kernel-devel-$(uname -r) kmod && (dnf -y install --skip-unavailable ffmpeg-free clinfo libva-utils mesa-va-drivers || true)'}
                '^rocky' {'dnf -y --setopt=install_weak_deps=False install cpio xz tar gcc gcc-c++ mokutil openssl make elfutils-libelf-devel kernel-devel-$(uname -r) kmod && (dnf -y install --skip-broken libva-utils mesa-va-drivers || true)'}
                '^arch$' {'version=$(pacman -Q linux | cut -d " " -f2); pacman -Sy --noconfirm --needed gcc make mokutil openssl efibootmgr grub kmod && (pacman -S --noconfirm linux-headers=$version || pacman -U --noconfirm "https://archive.archlinux.org/packages/l/linux-headers/linux-headers-$version-x86_64.pkg.tar.zst") && (pacman -S --noconfirm --needed ffmpeg clinfo libva-utils directx-headers || true)'}
                '^leap' {'version=$(rpm -qf --qf "%{VERSION}-%{RELEASE}" /boot/vmlinuz-$(uname -r)); zypper --non-interactive install --no-recommends gcc gcc-c++ mokutil openssl make gawk libelf-devel kernel-default-devel=$version kernel-devel=$version kmod && (zypper --non-interactive install libva-utils clinfo || true)'}
            }
            $prep="sudo -n env DEBIAN_FRONTEND=noninteractive http_proxy=$proxy https_proxy=$proxy sh -c '$prepare'"
            & ssh.exe @ssh "tester@$ip" $prep *> "$log/dependencies.txt"
            if($LASTEXITCODE){
                $update=switch -Regex ($base){
                    '^(fedora|rocky)' {'dnf -y --setopt=install_weak_deps=False install kernel kernel-devel gcc gcc-c++ make mokutil openssl elfutils-libelf-devel kmod && dnf -y upgrade kernel kernel-devel'}
                    '^arch$' {'pacman -Syu --noconfirm --needed linux linux-headers gcc make kmod libelf ffmpeg mokutil openssl efibootmgr grub'}
                    '^leap' {
                        & scp.exe @ssh "$PSScriptRoot/prepare-leap-kernel" "tester@${ip}:gpupv-prepare-leap-kernel"
                        if($LASTEXITCODE){throw 'Could not transfer the Leap kernel selector'}
                        'sh /home/tester/gpupv-prepare-leap-kernel'
                    }
                }
                if(!$update){throw "Guest dependencies failed ($LASTEXITCODE)"}
                $before=& ssh.exe @ssh "tester@$ip" 'cat /proc/sys/kernel/random/boot_id'
                & ssh.exe @ssh "tester@$ip" "sudo -n env http_proxy=$proxy https_proxy=$proxy sh -ec '$update' && sudo -n systemd-run --on-active=2s /usr/bin/systemctl reboot" *> "$log/kernel-update.txt"
                if($LASTEXITCODE){throw 'Official kernel and headers update failed'}
                Start-Sleep 12
                $ip=Connect-Guest $vm $ssh
                $after=& ssh.exe @ssh "tester@$ip" 'cat /proc/sys/kernel/random/boot_id; uname -r; test -f /lib/modules/$(uname -r)/build/Makefile'
                if($LASTEXITCODE -or $after[0] -eq $before){throw 'Updated kernel and headers not active'}
                @($before)+@($after) | Out-File "$log/kernel-update-boot.txt"
            }
            $dkmsTest=$base -eq 'debian-13' -and $vendor -eq 'Intel' -and !$SshPush
            if($dkmsTest){
                & ssh.exe @ssh "tester@$ip" "sudo -n env DEBIAN_FRONTEND=noninteractive http_proxy=$proxy https_proxy=$proxy apt-get install --no-install-recommends -y dkms" *> "$log/dkms-prerequisite.txt"
                if($LASTEXITCODE){throw 'Could not provision DKMS for signing regression'}
            }
            if($base -eq 'arch'){
                $fixture=Join-Path $root '.tools/gpupv-test-arch-shim.tar'
                if(!(Test-Path $fixture)){throw 'Arch requires an isolated signed shim fixture (see tests/prepare-arch-shim)'}
                & scp.exe @ssh "$PSScriptRoot/prepare-arch-shim" $fixture "tester@${ip}:"
                if($LASTEXITCODE){throw 'Could not transfer Arch test shim'}
                & ssh.exe @ssh "tester@$ip" 'sudo -n sh prepare-arch-shim gpupv-test-arch-shim.tar' *> "$log/arch-shim-setup.txt"
                if($LASTEXITCODE){throw 'Arch shim setup failed'}
            }
            & scp.exe @ssh "$root/guest/gpupv-guest" "$PSScriptRoot/prepare-test-mok" "tester@${ip}:"
            if($LASTEXITCODE){throw 'Cannot transfer test enrollment scripts'}
            $pass=[guid]::NewGuid().ToString('N').Substring(0,12)
            $request=$pass | ssh.exe @ssh "tester@$ip" 'sudo -n python3 prepare-test-mok gpupv-guest' 2>&1
            $status=$LASTEXITCODE
            $request | Out-File "$log/mok-request.txt"
            if($status){throw "MOK request failed ($status)"}
            if($request -contains 'enrollment_requested'){
                & "$PSScriptRoot/Confirm-TestMok.ps1" -Id $vm.Id -Password $pass | Out-File "$log/shim-menus.txt"
                Start-Sleep 8
                $ip=Connect-Guest $vm $ssh
            }
            & ssh.exe @ssh "tester@$ip" 'mokutil --sb-state; cat /proc/sys/kernel/random/boot_id; sudo -n mokutil --list-enrolled | grep -E "Issuer:|Fingerprint:"' *> "$log/mok-trust.txt"
            & "$PSScriptRoot/Invoke-Acceptance.ps1" -Id $vm.Id -Key $Key -Gpu $gpu[0].Name -Address $ip -Iso $media -Dkms:$dkmsTest *> "$log/run.txt"
            'PASS'|Set-Content "$log/outcome.txt"
        }catch{
            $_.Exception.Message|Set-Content "$log/outcome.txt"
            if($ip){
                try{$ip=Connect-Guest $vm $ssh}catch{$ip=$null}
            }
            if($ip){& ssh.exe @ssh "tester@$ip" 'id; uname -a; ls -l /dev/dxg; sudo -n dmesg | grep -Ei "dxg|vmbus|hv_pci"; ls -l /sys/bus/pci/devices/*/driver; df -h /; ls -l /lib/modules/$(uname -r)/build' *> "$log/diagnostic.txt"}
        }finally{
            if((Get-VM -Id $vm.Id).State -ne 'Off'){Stop-VM -VM $vm -TurnOff -Force}
            & "$PSScriptRoot/Remove-TestVM.ps1" -Id $vm.Id | Out-File "$log/cleanup.txt"
        }
    }
}








