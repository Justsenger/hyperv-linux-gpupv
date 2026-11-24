# Run on a VM created by New-TestVM.ps1, with the chosen GPU already attached.
param([Parameter(Mandatory)][guid]$Id,[Parameter(Mandatory)][string]$Key,
      [Parameter(Mandatory)][string]$Gpu,[Parameter(Mandatory)][string]$Address,[string]$Iso,[switch]$Dkms,[string]$CodecFixture)
$ErrorActionPreference='Stop'
$vm=Get-VM -Id $Id
if($vm.Name -notmatch '^gpupv-test-[0-9a-f]{32}$'){throw 'Unexpected test VM name'}
$root=Split-Path $PSScriptRoot
$dir=Join-Path $root ".test/$($vm.Name)"
if((Get-Content -LiteralPath "$dir/vm-id.txt") -ne $Id.ToString()){throw 'Test VM ownership mismatch'}
$cards=@(Get-VMGpuPartitionAdapter -VM $vm)
if($cards.Count -ne 1 -or $cards[0].InstancePath -ne $Gpu){throw 'Select the exact attached partition path'}
$report=New-Item -Type Directory "$root/artifacts/reports/$($vm.Name)-$([guid]::NewGuid().ToString('N').Substring(0,8))"
[ordered]@{startUtc=[DateTime]::UtcNow.ToString('o');vm=$vm.Name;vmId=$Id;gpu=$Gpu;hostBuild=[Environment]::OSVersion.Version.ToString();delivery=$(if($Iso){'iso'}else{'ssh'});dkms=$Dkms.IsPresent} | ConvertTo-Json | Set-Content "$report/run-context.json"
$ssh=@('-i',$Key,'-o','BatchMode=yes','-o','ConnectTimeout=5','-o','ServerAliveInterval=5','-o','ServerAliveCountMax=2','-o','StrictHostKeyChecking=accept-new','-o',"HostKeyAlias=$Id",'-o',"UserKnownHostsFile=$dir/known_hosts")
$target="tester@$Address"
function Invoke-Guest($Step,$Cmd){
    $out=& ssh.exe @ssh $target $Cmd 2>&1
    $rc=$LASTEXITCODE
    if($rc -eq 255 -and $Step -in 'intel-api-diagnostics','dmesg-after-workload','clean','clean-after-reboot','uninstall','module-trust-after-boot'){
        $out | Out-File "$report/$Step-transport.txt"
        $newIp=(Resolve-DnsName "$($vm.Name).mshome.net" -Type A -ErrorAction SilentlyContinue | Where-Object IPAddress | Select-Object -First 1 -ExpandProperty IPAddress)
        if($newIp){
            $next="tester@$newIp"
            $identity=& ssh.exe @ssh $next 'cat /proc/sys/kernel/hostname' 2>$null
            if($LASTEXITCODE -eq 0 -and $identity -eq $vm.Name){
                $script:target=$next
                $out=& ssh.exe @ssh $next $Cmd 2>&1
                $rc=$LASTEXITCODE
            }
        }
    }
    $out | Out-File "$report/$Step.txt"
    if($rc){throw "$Step failed with exit $rc"}
    $out
}
$identity=Invoke-Guest 'identity' 'cat /proc/sys/kernel/hostname'
if($identity[-1] -ne $vm.Name -and "$identity" -ne $vm.Name){throw 'SSH host name differs from owned VM'}
function Restart-TestGuest($Label){
    $old=Invoke-Guest "$Label-before" 'cat /proc/sys/kernel/random/boot_id'
    $null=Invoke-Guest "$Label-request" 'sudo -n systemd-run --on-active=3s /usr/bin/systemctl reboot'
    $until=(Get-Date).AddMinutes(5)
    while((Get-Date) -lt $until){
        Start-Sleep 4
        $mac=(Get-VMNetworkAdapter -VM $vm).MacAddress
        $ips=Get-NetNeighbor -AddressFamily IPv4 | Where-Object {($_.LinkLayerAddress -replace '-','') -eq $mac} | Select-Object -ExpandProperty IPAddress
        $dns=@(Resolve-DnsName "$($vm.Name).mshome.net" -Type A -ErrorAction SilentlyContinue | Where-Object IPAddress | Select-Object -ExpandProperty IPAddress)
        foreach($candidate in ($dns+@($ips)+@($Address) | Select-Object -Unique)){
            $next=& ssh.exe @ssh "tester@$candidate" 'cat /proc/sys/kernel/hostname /proc/sys/kernel/random/boot_id' 2>$null
            if($LASTEXITCODE -eq 0 -and $next.Count -eq 2 -and $next[0] -eq $vm.Name -and $next[1] -match '^[a-f0-9-]{36}$' -and $next[1] -ne $old){
                $next | Out-File "$report/$Label-after.txt"
                return "tester@$candidate"
            }
        }
    }
    throw 'No distinct post-reboot boot ID observed'
}
$tool='/usr/local/bin/gpupv-guest'
$environment=Invoke-Guest 'environment' 'cat /etc/os-release && uname -a && id'
$environment
if(($environment -match '^ID="?arch"?$') -and (Get-VMFirmware -VM $vm).SecureBoot -eq 'Off'){
    & scp.exe @ssh "$PSScriptRoot/prepare-arch-signed-boot" "${target}:gpupv-prepare-signed-boot"
    if($LASTEXITCODE){throw 'Could not transfer the Arch UKI builder'}
    Invoke-Guest 'arch-uki' 'sudo -n sh gpupv-prepare-signed-boot'
    Invoke-Guest 'arch-shutdown' 'sudo -n systemd-run --on-active=2s /usr/bin/systemctl poweroff'
    $deadline=(Get-Date).AddMinutes(2)
    while((Get-VM -Id $Id).State -ne 'Off'){
        if((Get-Date) -gt $deadline){throw 'Arch did not power off for Secure Boot'}
        Start-Sleep 2
    }
    Set-VMFirmware -VM $vm -EnableSecureBoot On -SecureBootTemplate MicrosoftUEFICertificateAuthority
    Start-VM -VM $vm
    $deadline=(Get-Date).AddMinutes(4)
    do{
        Start-Sleep 3
        $ip=(Resolve-DnsName "$($vm.Name).mshome.net" -Type A -ErrorAction SilentlyContinue | Where-Object IPAddress | Select-Object -First 1 -ExpandProperty IPAddress)
        if(!$ip){continue}
        $target="tester@$ip"
        $name=& ssh.exe @ssh $target 'cat /proc/sys/kernel/hostname' 2>$null
        if($LASTEXITCODE -eq 0 -and $name -eq $vm.Name){break}
    }while((Get-Date) -lt $deadline)
    Invoke-Guest 'arch-signed-boot' 'set -eu; cat /proc/sys/kernel/hostname; uname -r; mokutil --sb-state | grep "SecureBoot enabled"; cat /proc/cmdline'
}
$leap=($environment -match '^ID="?opensuse-leap"?$')
if($leap){
    & scp.exe @ssh "$PSScriptRoot/leap-module-policy" "${target}:gpupv-leap-module-policy"
    if($LASTEXITCODE){throw 'Could not transfer test module policy helper'}
    Invoke-Guest 'third-party-module-policy' 'sudo -n sh "$HOME/gpupv-leap-module-policy" enable'
}
# Some Ubuntu cloud images omit the virtual PCI controller from their kernel package.
$transportPrep='set -eu; . /etc/os-release; if test "$ID" = ubuntu && ! modinfo pci_hyperv >/dev/null 2>&1; then sudo -n env DEBIAN_FRONTEND=noninteractive apt-get -o DPkg::Lock::Timeout=120 install -y --no-install-recommends "linux-modules-extra-$(uname -r)"; sudo -n modprobe pci_hyperv; sudo -n udevadm settle; fi; for d in /sys/bus/pci/devices/*; do if test -r "$d/vendor"; then cat "$d/vendor" "$d/device"; fi; done'
Invoke-Guest 'transport-prerequisite' $transportPrep
if($Gpu -like '*VEN_8086*'){
    if($environment -match '^ID="?rocky"?$'){
        Invoke-Guest 'rocky-drm-modules' 'grep -E "DRM_(VGEM|VKMS|HYPERV)" /boot/config-$(uname -r); if ! /usr/sbin/modinfo vgem >/dev/null 2>&1 && ! /usr/sbin/modinfo vkms >/dev/null 2>&1; then sudo -n timeout 150 dnf -y install "kernel-modules-extra-$(uname -r)" || true; fi; /usr/sbin/modinfo -F filename vkms || true'
    }
    $icd='set -u; . /etc/os-release; case "$ID" in ubuntu|debian) if apt-cache show intel-opencl-icd >/dev/null 2>&1; then sudo -n env DEBIAN_FRONTEND=noninteractive timeout 240 apt-get -o DPkg::Lock::Timeout=100 install -y --no-install-recommends intel-opencl-icd; echo "package exit=$?"; fi;; fedora) sudo -n timeout 180 dnf -y --setopt=install_weak_deps=False install --skip-unavailable intel-compute-runtime ffmpeg-free libva-utils mesa-va-drivers clinfo; echo "package exit=$?";; rocky) sudo -n timeout 180 dnf -y --setopt=install_weak_deps=False install intel-compute-runtime; echo "OpenCL package exit=$?"; sudo -n timeout 180 dnf -y --setopt=install_weak_deps=False --skip-broken install libva-utils mesa-va-drivers; echo "VA package exit=$?";; arch) sudo -n timeout 180 pacman -S --needed --noconfirm intel-compute-runtime; echo "OpenCL exit=$?"; sudo -n timeout 180 pacman -S --needed --noconfirm onevpl-intel-gpu intel-media-driver; echo "package exit=$?";; opensuse*) sudo -n timeout 180 zypper --non-interactive install --no-recommends intel-opencl; echo "package exit=$?";; esac; ls -l /etc/OpenCL/vendors 2>/dev/null || true'
    Invoke-Guest 'opencl-icd-prerequisite' $icd
}
$installArgs=if($Dkms){' --dkms'}else{''}
if($Dkms -and !$Iso){throw 'Select an ISO for DKMS acceptance'}
if($Iso){
    $isoPath=(Resolve-Path -LiteralPath $Iso).Path
    $mediaDeadline=(Get-Date).AddMinutes(8)
    while((Get-Date) -lt $mediaDeadline){
        $drives=@(Get-VMDvdDrive -VM $vm)
        if(($drives | Where-Object Path -eq $isoPath) -or !($drives | Where-Object {!$_.Path})){break}
        Start-Sleep 4
    }
    if(!(Get-VMDvdDrive -VM $vm | Where-Object Path -eq $isoPath)){throw 'Attach the selected deployment ISO to the owned VM first'}
    Invoke-Guest 'install-first' ('set -eu; sudo -n mkdir -p /mnt/gpupv; dev=$(sudo -n blkid -L GPUPV); sudo -n mount -o ro "$dev" /mnt/gpupv; sha256sum /mnt/gpupv/guest/gpupv-guest /mnt/gpupv/kernel/drivers/hv/dxgkrnl/dxgvmbus.c /mnt/gpupv/kernel/drivers/hv/dxgkrnl/dxgvmbus.h; sudo -n sh /mnt/gpupv/guest/setup'+$installArgs)
}else{
    & "$root/host/gpupv-host.ps1" push -Gpu $Gpu -Destination $target -IdentityFile $Key -KnownHostsFile "$dir/known_hosts" -HostKeyAlias $Id *> "$report/install-first.txt"
}
$failures=[Collections.Generic.List[string]]::new()
Invoke-Guest 'install-repeat' "sudo -n $tool install$installArgs"
Invoke-Guest 'installed-module' 'p=$(sudo -n modinfo -n dxgkrnl) && readlink -f "$p" && ls -lZ "$p" && sudo -n modinfo -F signer dxgkrnl'
$target=Restart-TestGuest 'installed-boot'
if(($environment -match '^ID="?rocky"?$') -and $Gpu -like '*VEN_8086*'){
    Invoke-Guest 'rocky-vkms' 'if ! /usr/sbin/modinfo vgem >/dev/null 2>&1; then sudo -n modprobe vkms || true; sudo -n udevadm settle; fi; ls -l /sys/class/drm'
}
try {
    Invoke-Guest 'access' 'id && test "$(id -u)" -ne 0 && ls -l /dev/dxg && test -r /dev/dxg && test -w /dev/dxg && /usr/local/bin/gpupv-guest check'
    Invoke-Guest 'module-trust-after-boot' 'set -eu; mokutil --sb-state; signer=$(sudo -n modinfo -F signer dxgkrnl); test -n "$signer"; echo "$signer"; sudo -n modinfo -F sig_key dxgkrnl; cat /sys/module/dxgkrnl/taint; if grep -q E /sys/module/dxgkrnl/taint; then exit 1; fi'
} catch {
    $failures.Add($_.Exception.Message)
}
$dmesg=Invoke-Guest 'dmesg' 'sudo -n dmesg'
if($dmesg -match '(?i)kernel panic|BUG:|Oops:|dxg(?:krnl|k)?.*(error|fail|timeout)'){$failures.Add('Kernel diagnostic requires review')}
Invoke-Guest 'workload-trace' 'for ctl in /proc/dynamic_debug/control /sys/kernel/debug/dynamic_debug/control; do if sudo -n test -f "$ctl"; then echo "module dxgkrnl format gpupv +p" | sudo -n tee "$ctl" && exit 0; fi; done; echo "dynamic debug unavailable"'
$verify="$tool verify"
if($Gpu -like '*VEN_10DE*'){
    $codecs=Invoke-Guest 'native-codecs' 'if command -v ffmpeg >/dev/null; then ffmpeg -version | head -1; ffmpeg -hide_banner -encoders 2>/dev/null | grep -w h264_nvenc || true; ffmpeg -hide_banner -decoders 2>/dev/null | grep -w h264_cuvid || true; else echo ffmpeg_unavailable; fi'
    if(!($codecs -match 'h264_nvenc') -or !($codecs -match 'h264_cuvid')){
        if(!$CodecFixture){$CodecFixture=Join-Path $root '.tools/ffmpeg-va-ubuntu24-x64.tgz'}
        if(Test-Path -LiteralPath $CodecFixture){
            & scp.exe @ssh -- $CodecFixture ("${target}:gpupv-codec.tgz")
            if($LASTEXITCODE){throw 'Cannot transfer the isolated FFmpeg test runtime'}
            $digest=(Get-FileHash -LiteralPath $CodecFixture).Hash.ToLowerInvariant()
            $prepare='set -eu; echo "HASH  gpupv-codec.tgz" | sha256sum -c -; mkdir -m 700 gpupv-codec; tar -xzf gpupv-codec.tgz -C gpupv-codec; cat gpupv-codec/packages; gpupv-codec/ffmpeg -version | head -1'
            Invoke-Guest 'isolated-codecs' ($prepare.Replace('HASH',$digest))
            # Fedora aliases /usr/sbin to /usr/bin. Run the isolated media check
            # with its own process PATH so the native FFmpeg cannot shadow it.
            $verify=@'
set -eu
test "$(id -u)" -ne 0
export PATH="$HOME/gpupv-codec:$PATH"
test "$(command -v ffmpeg)" = "$HOME/gpupv-codec/ffmpeg"
base=/opt/hyperv-linux-gpupv
gpu=$(python3 -c "import json; print(json.load(open('/opt/hyperv-linux-gpupv/device.json'))['name'])")
printf 'boot_id=%s uid=%s gpu=%s\n' "$(cat /proc/sys/kernel/random/boot_id)" "$(id -u)" "$gpu"
/usr/local/bin/nvidia-smi --query-gpu=name,driver_version,memory.total --format=csv
python3 "$base/guest/cuda-compute.py" "$gpu"
ffmpeg -version | head -1
exec sh "$base/guest/verify-codec"
'@
            $verify=$verify.Replace("`r",'')
        }
    }
}
try{Invoke-Guest 'workload' $verify}catch{
    $nativeFailure=$_.Exception.Message
    $failures.Add($nativeFailure)
    if($Gpu -like '*VEN_10DE*' -and (Test-Path "$report/isolated-codecs.txt")){
        Invoke-Guest 'isolated-codec-loader' 'LD_DEBUG=libs,versions "$HOME/gpupv-codec/ffmpeg" -hide_banner -loglevel error -f lavfi -i testsrc2=size=320x240:rate=1 -frames:v 1 -c:v h264_nvenc -f null - 2>&1 | grep -Ei "libcuda|libnvidia|version lookup error|not found|undefined symbol|cannot load" | tail -120; true'
    }
    if($Gpu -like '*VEN_8086*'){
        & scp.exe @ssh "$PSScriptRoot/check-intel-video-profiles" ("${target}:gpupv-video-profiles")
        if(!$LASTEXITCODE){Invoke-Guest 'intel-video-profiles' 'sh gpupv-video-profiles || echo "profiles_exit=$?"'}
        & scp.exe @ssh "$root/guest/verify-intel-codec" ("${target}:gpupv-codec-comparison")
        if(!$LASTEXITCODE){
            Invoke-Guest 'intel-codec-comparison' 'if cmp -s gpupv-codec-comparison /opt/hyperv-linux-gpupv/guest/verify-intel-codec; then echo identical_to_installed; else sh gpupv-codec-comparison; echo "comparison_exit=$?"; fi'
            $vaFixture=Join-Path $root '.tools/ffmpeg-va-ubuntu24-x64.tgz'
            if(Test-Path -LiteralPath $vaFixture){
                & scp.exe @ssh $vaFixture ("${target}:gpupv-va-runtime.tgz")
                if(!$LASTEXITCODE){
                    $hash=(Get-FileHash -LiteralPath $vaFixture).Hash.ToLowerInvariant()
                    $isolated='set -eu; echo "HASH  gpupv-va-runtime.tgz" | sha256sum -c -; d=$(mktemp -d "$HOME/gpupv-va.XXXXXXXX"); trap ''rm -rf "$d"'' EXIT; tar -xzf gpupv-va-runtime.tgz -C "$d"; cat "$d/packages"; sudo -n modprobe vgem || true; sudo -n udevadm settle; ls -l /dev/dri || true; export PATH="$d:$PATH" LIBVA_DRIVERS_PATH="$d/lib"; set +e; if /usr/local/bin/gpupv-guest --help | grep -q -- --va-runtime; then /usr/local/bin/gpupv-guest verify --va-runtime "$d"; echo "isolated_product_exit=$?"; else sh gpupv-codec-comparison; echo "isolated_va_exit=$?"; fi; if test -f gpupv-video-profiles; then sh gpupv-video-profiles || echo "isolated_profiles_exit=$?"; fi'
                    try {
                        $observations=Invoke-Guest 'isolated-intel-va' ($isolated.Replace('HASH',$hash))
                        $observations
                        if($observations -contains 'isolated_product_exit=0'){
                            [void]$failures.Remove($nativeFailure)
                        }elseif($environment -match '^ID="?rocky"?$'){
                            $rpm=Join-Path $root '.tools/rocky-vgem-source/kernel-5.14.0-741.22.1.el9_9.src.rpm'
                            if(Test-Path -LiteralPath $rpm){
                                & scp.exe @ssh $rpm "$PSScriptRoot/prepare-rocky-vgem" ("${target}:")
                                if($LASTEXITCODE){throw 'Rocky diagnostic source transfer failed'}
                                Invoke-Guest 'rocky-signed-vgem' 'sudo -n sh prepare-rocky-vgem kernel-5.14.0-741.22.1.el9_9.src.rpm'
                                try {
                                    $vgem=Invoke-Guest 'isolated-intel-vgem' ($isolated.Replace('HASH',$hash))
                                    $vgem
                                    if($vgem -contains 'isolated_product_exit=0'){[void]$failures.Remove($nativeFailure)}
                                }finally{Invoke-Guest 'rocky-vgem-unload' 'sudo -n rmmod vgem && test ! -e /sys/module/vgem'}
                            }
                        }
                    }
                    catch { $failures.Add($_.Exception.Message) }
                }
            }
        }
        Invoke-Guest 'intel-api-diagnostics' 'id; ls -l /dev/dxg /dev/dri; ldd /usr/lib/wsl/lib/libdxcore.so; ldd /usr/lib/wsl/lib/libd3d12.so; for umd in /usr/lib/wsl/drivers/*/libigd12umd64.so; do test -f "$umd" && ldd "$umd"; done; if command -v clinfo >/dev/null; then timeout 30 clinfo --list; fi; echo diagnostic_collection_finished'
    }
}
$after=Invoke-Guest 'dmesg-after-workload' 'sudo -n dmesg'
if($after -match '(?i)kernel panic|BUG:|Oops:|dxg(?:krnl|k)?.*(error|fail|timeout)|WARNING:.*dxg'){$failures.Add('Kernel diagnostic after workload requires review')}
if(!$Iso -or $environment -match '^ID="?(fedora|rocky)"?$'){
    # Observe a second ordinary process after saving the acceptance kernel log.
    # This audit module only reads glibc call arguments and leaves return values intact.
    & scp.exe @ssh "$PSScriptRoot/observe-dxcore-queries.c" ("${target}:")
    if(!$LASTEXITCODE){
        $audit='set -eu; d=$(mktemp -d); trap ''rm -rf "$d"'' EXIT; cc -O2 -shared -fPIC observe-dxcore-queries.c -o "$d/observer.so"; if test -x /opt/hyperv-linux-gpupv/guest/intel-compute && test -e /usr/lib/wsl/drivers/*/libigd12umd64.so; then LD_AUDIT="$d/observer.so" /opt/hyperv-linux-gpupv/guest/intel-compute; else LD_AUDIT="$d/observer.so" nvidia-smi --query-gpu=name,driver_version,memory.total --format=csv; fi'
        try{Invoke-Guest 'dxcore-call-metadata' $audit}catch{Write-Warning $_.Exception.Message}
    }
}
Invoke-Guest 'uninstall' "sudo -n $tool uninstall"
if($leap){Invoke-Guest 'restore-module-policy' 'sudo -n sh "$HOME/gpupv-leap-module-policy" restore'}
$clean='set -eu; for p in /usr/local/bin/nvidia-smi /usr/src/gpupv-dxgkrnl-0.1 /var/lib/dkms/gpupv-dxgkrnl/0.1 /opt/hyperv-linux-gpupv /sys/module/dxgkrnl /dev/dxg /usr/local/bin/gpupv-guest /usr/lib/wsl/lib /usr/lib/wsl/drivers /etc/modules-load.d/gpupv.conf /etc/udev/rules.d/70-gpupv.rules /etc/modprobe.d/gpupv.conf /etc/ld.so.conf.d/gpupv.conf /lib/modules/$(uname -r)/updates/gpupv/dxgkrnl.ko; do test ! -e "$p" && test ! -L "$p" || exit 1; done; command -v modinfo >/dev/null || PATH=/usr/sbin:/sbin:$PATH; command -v modinfo >/dev/null; if modinfo dxgkrnl >/dev/null 2>&1; then exit 1; fi; echo managed_paths_clean'
Invoke-Guest 'clean' $clean
$target=Restart-TestGuest 'uninstalled-boot'
Invoke-Guest 'clean-after-reboot' $clean
$journal=Invoke-Guest 'modules-load-journal' 'sudo -n journalctl -b -u systemd-modules-load --no-pager'
$messages=Invoke-Guest 'modules-load-messages' 'sudo -n journalctl -b -u systemd-modules-load -o cat --no-pager'
if($messages -match '(?i)(gpupv|dxgkrnl)'){$failures.Add('Stale module load after uninstall')}
@{vm=$vm.Name;gpu=$Gpu;hostBuild=[Environment]::OSVersion.Version.ToString();passed=($failures.Count -eq 0);failures=@($failures)} | ConvertTo-Json | Set-Content "$report/result.json"

if($failures.Count){throw ($failures -join ", ")}
