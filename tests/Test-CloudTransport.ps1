# Measure the pre-install GPU transport independently of installation or workloads.
param([Parameter(Mandatory)][string]$Target,[Parameter(Mandatory)][string]$QemuImg,
      [Parameter(Mandatory)][string]$Key,[int]$MemoryMiB=768,[guid]$ResumeId,[string]$GpuPath)
$ErrorActionPreference='Stop'
$repo=Split-Path $PSScriptRoot
$report=New-Item -Type Directory "$repo/artifacts/reports/transport-$Target-$([guid]::NewGuid().ToString('N').Substring(0,8))"
$cards=@(Get-VMHostPartitionableGpu)
if($GpuPath){$cards=@($cards|Where-Object Name -eq $GpuPath)}
if(!$cards){throw 'No partitionable devices'}
if($ResumeId){
    $vm=Get-VM -Id $ResumeId
    if($vm.Name -notmatch '^gpupv-test-[0-9a-f]{32}$' -or $vm.State -ne 'Off'){throw 'Expected a stopped test VM'}
}else{
    $image=& "$PSScriptRoot/Get-CloudImage.ps1" -Target $Target
    $image | ConvertTo-Json | Set-Content "$report/image.json"
    $result=& "$PSScriptRoot/New-TestVM.ps1" -Image $image.Image -Sha256 $image.Sha256 -QemuImg $QemuImg -PublicKey "$Key.pub" -MemoryMiB $MemoryMiB -GpuPath $cards[0].Name
    $vm=Get-VM -Id ($result | Where-Object Id | Select-Object -Last 1).Id
}
$dir="$repo/.test/$($vm.Name)"
if($vm.Id.ToString() -ne (Get-Content "$dir/vm-id.txt")){throw 'VM ID mismatch'}
try {
    if($ResumeId){
        $snapshot=Get-VMSnapshot -VM $vm -Name gpupv-test-clean
        Restore-VMSnapshot -VMSnapshot $snapshot -Confirm:$false
        Add-VMGpuPartitionAdapter -VM $vm -InstancePath $cards[0].Name
        Start-VM -VM $vm
    }
    for($i=0;$i -lt $cards.Count;$i++){
        if($i -gt 0){
            Get-VMGpuPartitionAdapter -VM $vm | Remove-VMGpuPartitionAdapter
            Add-VMGpuPartitionAdapter -VM $vm -InstancePath $cards[$i].Name
            Start-VM -VM $vm
        }
        $log="$report/adapter-$i.txt"
        Get-VMGpuPartitionAdapter -VM $vm | select InstancePath,InstanceId | Out-File $log
        $opts=@('-i',$Key,'-o','BatchMode=yes','-o','ConnectTimeout=3','-o','StrictHostKeyChecking=accept-new','-o',"UserKnownHostsFile=$dir/known-$($report.Name)")
        $mac=$vm.NetworkAdapters[0].MacAddress
        $deadline=(Get-Date).AddMinutes(3)
        $connected=$false
        while((Get-Date) -lt $deadline){
            $addr=Get-NetNeighbor -AddressFamily IPv4 | Where-Object {($_.LinkLayerAddress -replace '-','') -eq $mac} | select -First 1 -ExpandProperty IPAddress
            if(!$addr){$addr=(Resolve-DnsName "$($vm.Name).mshome.net" -Type A -ErrorAction SilentlyContinue | Select-Object -First 1).IPAddress}
            if($addr){
                $hostName=& ssh.exe @opts "tester@$addr" 'cat /proc/sys/kernel/hostname' 2>>"$report/ssh-$i.txt"
                if($LASTEXITCODE -eq 0 -and $hostName -eq $vm.Name){$connected=$true;break}
            }
            Start-Sleep 3
        }
        if(!$connected){throw "Guest SSH identity unconfirmed for $($vm.Name)"}
        $out=& ssh.exe @opts "tester@$addr" 'id; uname -a; cat /etc/os-release; cat /proc/sys/kernel/random/boot_id; for f in /sys/bus/vmbus/devices/*/class_id; do cat "$f"; done' 2>&1
        $rc=$LASTEXITCODE
        $out | Out-File $log -Append
        if($rc -ne 0 -or !($out -match 'dde9cbc0-5060-4436-9448-ea1254a5d177') -or !($out -match '6e382d18-3336-4f4b-acc4-2b7703d4df4a')){throw 'GPU VMBus channel enumeration incomplete'}
        & ssh.exe @opts "tester@$addr" 'sudo -n shutdown -h now' 2>>"$report/ssh-$i.txt"
        $until=(Get-Date).AddMinutes(2)
        while((Get-VM -Id $vm.Id).State -ne 'Off' -and (Get-Date) -lt $until){Start-Sleep 2}
        if((Get-VM -Id $vm.Id).State -ne 'Off'){throw 'Guest did not shut down cleanly'}
    }
} finally {
    if((Get-VM -Id $vm.Id).State -ne 'Off'){Stop-VM -VM $vm -TurnOff -Confirm:$false}
}

