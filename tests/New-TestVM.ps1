param([Parameter(Mandatory)][string]$Image,[Parameter(Mandatory)][string]$Sha256,
      [Parameter(Mandatory)][string]$QemuImg,[Parameter(Mandatory)][string]$PublicKey,
      [string]$GpuPath,[string]$DeploymentIso,[switch]$SecureBoot,[switch]$NoCheckpoint,[int]$MemoryMiB=1024,[string]$Switch='Default Switch')
$ErrorActionPreference='Stop'
if ((Get-FileHash -LiteralPath $Image).Hash -ne $Sha256){throw 'Image checksum mismatch'}
$key=(Get-Content -Raw -LiteralPath $PublicKey).Trim()
if ($key -notmatch '^ssh-ed25519 [A-Za-z0-9+/=]+(?: [^\r\n]*)?$'){throw 'Expected an Ed25519 public key'}
$name='gpupv-test-'+[guid]::NewGuid().ToString('N')
$dir=Join-Path (Split-Path $PSScriptRoot) ".test/$name"
$seed=New-Item -Type Directory "$dir/seed"
"instance-id: $name`nlocal-hostname: $name" | Set-Content "$seed/meta-data" -Encoding ascii
@"
#cloud-config
ssh_authorized_keys:
  - $key
users:
  - default
  - name: tester
    groups: [sudo, wheel, video]
    sudo: ALL=(ALL) NOPASSWD:ALL
    shell: /bin/sh
    ssh_authorized_keys:
      - $key
ssh_pwauth: false
"@ | Set-Content "$seed/user-data" -Encoding ascii
if((Split-Path -Leaf $Image) -like 'gpupv-test-ubuntu-*'){
    @"
apt:
  primary:
    - arches: [default]
      uri: https://archive.ubuntu.com/ubuntu
  security:
    - arches: [default]
      uri: https://security.ubuntu.com/ubuntu
"@ | Add-Content "$seed/user-data" -Encoding ascii
}
$iso="$dir/gpupv-test-seed.iso"
& "$PSScriptRoot/../host/New-GpuPvIso.ps1" -Source $seed -Output $iso -Label cidata
$disk="$dir/gpupv-test-root.vhdx"
& $QemuImg convert -O vhdx -o subformat=dynamic $Image $disk
if($LASTEXITCODE){throw 'Conversion failed'}
fsutil sparse setflag $disk 0
if($LASTEXITCODE){throw 'Cannot prepare non-sparse VHDX'}
if((Get-VHD -Path $disk).Size -lt 32GB){Resize-VHD -Path $disk -SizeBytes 32GB}
$vm=New-VM -Name $name -Path $dir -Generation 2 -MemoryStartupBytes ($MemoryMiB*1MB) -VHDPath $disk -SwitchName $Switch
$vm.Id.ToString() | Set-Content "$dir/vm-id.txt"
Set-VM -VM $vm -AutomaticCheckpointsEnabled $false -CheckpointType Standard -StaticMemory -GuestControlledCacheTypes $true -LowMemoryMappedIoSpace 1GB -HighMemoryMappedIoSpace 32GB
if ($SecureBoot){Set-VMFirmware -VM $vm -EnableSecureBoot On -SecureBootTemplate MicrosoftUEFICertificateAuthority}
else{Set-VMFirmware -VM $vm -EnableSecureBoot Off}
Set-VMComPort -VM $vm -Number 1 -Path "\\.\pipe\$name"
Add-VMDvdDrive -VM $vm -Path $iso
if($DeploymentIso){Add-VMDvdDrive -VM $vm -Path (Resolve-Path -LiteralPath $DeploymentIso).Path}
Set-VMFirmware -VM $vm -FirstBootDevice (Get-VMHardDiskDrive -VM $vm)
if(!$NoCheckpoint){Checkpoint-VM -VM $vm -SnapshotName gpupv-test-clean}
if($GpuPath){Add-VMGpuPartitionAdapter -VM $vm -InstancePath $GpuPath}
$deadline=(Get-Date).AddMinutes(40)
while($true){
    try{
        Start-VM -VM $vm -ErrorAction Stop
        break
    }catch{
        $memoryFailure=($_.Exception.Message -match '0x8007000[Ee]|0x800705[Aa][Aa]|insufficient.*memory|内存不足|内存资源不足')
        if(!$memoryFailure -or (Get-Date) -ge $deadline){
            if((Get-VM -Id $vm.Id).State -eq 'Off'){
                & "$PSScriptRoot/Remove-TestVM.ps1" -Id $vm.Id | Out-Host
            }
            throw
        }
        Start-Sleep -Seconds 30
    }
}
Get-VM -Id $vm.Id | Select-Object Name,Id,State





