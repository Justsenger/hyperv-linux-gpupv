param([Parameter(Mandatory)][guid]$Id)
$ErrorActionPreference='Stop'
$v=Get-VM -Id $Id
if($v.Name -notmatch '^gpupv-test-[0-9a-f]{32}$'){throw 'Unexpected VM name'}
$root=(Resolve-Path -LiteralPath (Join-Path (Split-Path $PSScriptRoot) '.test')).Path
$dir=(Resolve-Path -LiteralPath (Join-Path $root $v.Name)).Path
if([IO.Path]::GetDirectoryName($dir) -ne $root -or (Get-Item -LiteralPath $dir).Attributes.HasFlag([IO.FileAttributes]::ReparsePoint)){throw 'Unexpected VM directory'}
if((Get-Content -LiteralPath "$dir/vm-id.txt") -ne $Id.ToString()){throw 'Ownership record mismatch'}
$paths=@($v.ConfigurationLocation,$v.SnapshotFileLocation)+@(Get-VMHardDiskDrive -VM $v|Select-Object -ExpandProperty Path)
foreach($p in $paths){
    $actual=[IO.Path]::GetFullPath($p).TrimEnd('\')
    if($actual -ne $dir -and !$actual.StartsWith($dir+'\',[StringComparison]::OrdinalIgnoreCase)){throw "Resource outside test directory: $actual"}
}
if($v.State -ne 'Off'){throw 'Shut down this owned test VM before removing its resources'}
Remove-VM -VM $v -Force
if(Get-VM -Id $Id -ErrorAction SilentlyContinue){throw 'VM is still registered'}
Remove-Item -Recurse -Force -LiteralPath $dir
"Removed $Id $dir"

