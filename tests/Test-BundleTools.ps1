$ErrorActionPreference='Stop'
. "$PSScriptRoot/../host/BundleTools.ps1"
Assert-BundleArchitecture @{schemaVersion=1;arch='aarch64'} 'aarch64'
$rejected=$false
try { Assert-BundleArchitecture @{schemaVersion=1;arch='aarch64'} 'x86_64' } catch { $rejected=$true }
if(!$rejected){throw 'Wrong architecture accepted'}
$temp=[IO.Directory]::CreateTempSubdirectory('linuxpv-contract-test-')
try {
    $dest=$temp.CreateSubdirectory('lib')
    $first=Join-Path $temp.FullName first
    $second=Join-Path $temp.FullName second
    [IO.File]::WriteAllText($first,'one')
    [IO.File]::WriteAllText($second,'one')
    Add-DriverFile $first $dest.FullName 'alias.so'
    Add-DriverFile $second $dest.FullName 'alias.so'
    [IO.File]::WriteAllText($second,'two')
    $rejected=$false
    try{Add-DriverFile $second $dest.FullName 'alias.so'}catch{$rejected=$true}
    if(!$rejected -or [IO.File]::ReadAllText((Join-Path $dest.FullName alias.so)) -ne 'one'){throw 'Collision check failed'}
    $infPath=Join-Path $temp.FullName dual.inf
    @(
        '[DestinationDirs.NTamd64]', 'Export.NTamd64=11,"lxss\lib"',
        '[DestinationDirs.NTarm64]', 'Export.NTarm64=11,"lxss\lib"',
        '[Export.NTamd64]', 'driver.so,x64.so',
        '[Export.NTarm64]', 'driver.so,arm64.so'
    ) | Set-Content -LiteralPath $infPath
    foreach($arch in 'x86_64','aarch64'){
        $map=& "$PSScriptRoot/../host/Get-WslFileMap.ps1" -Inf $infPath -Arch $arch
        $expected=if($arch -eq 'x86_64'){'x64.so'}else{'arm64.so'}
        if($map['driver.so'] -ne $expected){throw "Wrong INF alias for $arch"}
    }
    'Architecture-decorated INF aliases: passed'
}finally{$temp.Delete($true)}
'architecture mismatch, matching aliases, conflicting aliases: passed'

$cards=@([pscustomobject]@{Name='GPU';Instance='pci-a';Pnp='pnp-a'},[pscustomobject]@{Name='GPU';Instance='pci-b';Pnp='pnp-b'})
$selected=@(Get-SelectedGpu $cards @('pnp-a','pci-b'))
if($selected.Count -ne 2){throw 'Lost multi-GPU selection'}
foreach($ids in (,@('GPU') + ,@('pci-a','absent') + ,@('pci-b','pci-b'))){
    $rejected=$false
    try{Get-SelectedGpu $cards $ids | Out-Null}catch{$rejected=$true}
    if(!$rejected){throw "Invalid selection accepted: $ids"}
}
'Single-name ambiguity, multiple matching PCI IDs, unknown and duplicate cards: passed'
