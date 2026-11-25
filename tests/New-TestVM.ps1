param([Parameter(Mandatory)][string]$Image,[Parameter(Mandatory)][string]$Sha256,
      [Parameter(Mandatory)][string]$QemuImg,[Parameter(Mandatory)][string]$PublicKey,
      [string]$GpuPath,[string]$DeploymentIso,[switch]$SecureBoot,[switch]$NoCheckpoint,[int]$MemoryMiB=1024,[string]$Switch='Default Switch',[switch]$ExHyperVMmio,[switch]$UseDifferencingDisk)
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
$armHost=[Runtime.InteropServices.RuntimeInformation]::OSArchitecture -eq 'Arm64'
if($armHost -and (Split-Path -Leaf $Image) -match '^gpupv-test-debian-(sid|testing)-'){
    @"
version: 2
ethernets:
  uplink:
    match:
      name: "e*"
    dhcp4: true
"@ | Set-Content "$seed/network-config" -Encoding ascii
}
if((Split-Path -Leaf $Image) -like 'gpupv-test-ubuntu-*'){
    $primary=if($armHost){'https://ports.ubuntu.com/ubuntu-ports'}else{'https://archive.ubuntu.com/ubuntu'}
    $security=if($armHost){$primary}else{'https://security.ubuntu.com/ubuntu'}
    @"
apt:
  primary:
    - arches: [default]
      uri: $primary
  security:
    - arches: [default]
      uri: $security
"@ | Add-Content "$seed/user-data" -Encoding ascii
}
$iso="$dir/gpupv-test-seed.iso"
& "$PSScriptRoot/../host/New-GpuPvIso.ps1" -Source $seed -Output $iso -Label cidata
$disk="$dir/gpupv-test-root.vhdx"
if($UseDifferencingDisk){
    $parent=Get-VHD -Path $Image
    if($parent.VhdFormat -ne 'VHDX' -or $parent.Size -lt 32GB -or $parent.Attached){throw 'Expected an offline VHDX parent of at least 32 GiB'}
    $null=New-VHD -Path $disk -ParentPath $parent.Path -Differencing
}else{
    & $QemuImg convert -O vhdx -o subformat=dynamic $Image $disk
    if($LASTEXITCODE){throw 'Conversion failed'}
    fsutil sparse setflag $disk 0
    if($LASTEXITCODE){throw 'Cannot prepare non-sparse VHDX'}
    if((Get-VHD -Path $disk).Size -lt 32GB){Resize-VHD -Path $disk -SizeBytes 32GB}
}
$vm=New-VM -Name $name -Path $dir -Generation 2 -MemoryStartupBytes ($MemoryMiB*1MB) -VHDPath $disk -SwitchName $Switch
$vm.Id.ToString() | Set-Content "$dir/vm-id.txt"
Set-VM -VM $vm -AutomaticCheckpointsEnabled $false -CheckpointType Standard -StaticMemory
if($armHost){
    $vm=Get-VM -Id $vm.Id
    $vm | Select-Object HighMemoryMappedIoBaseAddress,HighMemoryMappedIoSpace,LowMemoryMappedIoSpace | ConvertTo-Json | Set-Content "$dir/mmio-default.json"
    # Grow the aperture downwards. Extending past the ARM64 firmware window
    # prevents startup, while the default 512 MiB cannot fit the GPU offer.
    $highEnd=$vm.HighMemoryMappedIoBaseAddress+$vm.HighMemoryMappedIoSpace
    if($ExHyperVMmio){
        Set-VM -VM $vm -HighMemoryMappedIoBaseAddress (32768MB) -HighMemoryMappedIoSpace (31744MB) -LowMemoryMappedIoSpace (3584MB)
    }else{
        Set-VM -VM $vm -HighMemoryMappedIoBaseAddress ($highEnd-32GB) -HighMemoryMappedIoSpace 32GB
    }
    Get-CimInstance -Namespace root/virtualization/v2 -ClassName Msvm_VirtualSystemSettingData -Filter "VirtualSystemIdentifier='$($vm.Id)'" |
        Select-Object HighMmioGapBase,HighMmioGapSize,LowMmioGapSize | ConvertTo-Json | Set-Content "$dir/mmio-set.json"
}else{
    Set-VM -VM $vm -GuestControlledCacheTypes $true -LowMemoryMappedIoSpace 1GB -HighMemoryMappedIoSpace 32GB
}
if ($SecureBoot){Set-VMFirmware -VM $vm -EnableSecureBoot On -SecureBootTemplate MicrosoftUEFICertificateAuthority}
else{Set-VMFirmware -VM $vm -EnableSecureBoot Off}
Set-VMComPort -VM $vm -Number 1 -Path "\\.\pipe\$name"
Add-VMDvdDrive -VM $vm -Path $iso
if($DeploymentIso){Add-VMDvdDrive -VM $vm -Path (Resolve-Path -LiteralPath $DeploymentIso).Path}
Set-VMFirmware -VM $vm -FirstBootDevice (Get-VMHardDiskDrive -VM $vm)
if(!$NoCheckpoint){Checkpoint-VM -VM $vm -SnapshotName gpupv-test-clean}
if($GpuPath){Add-VMGpuPartitionAdapter -VM $vm -InstancePath $GpuPath}
try{& "$PSScriptRoot/Start-TestVM.ps1" -Id $vm.Id}catch{
    if((Get-VM -Id $vm.Id).State -eq 'Off'){
        & "$PSScriptRoot/Remove-TestVM.ps1" -Id $vm.Id | Out-Host
    }
    throw
}
Get-VM -Id $vm.Id | Select-Object Name,Id,State





