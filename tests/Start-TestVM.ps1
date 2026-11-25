# Allow other disposable tests to release static guest RAM before retrying.
param([Parameter(Mandatory)][guid]$Id)
$ErrorActionPreference='Stop'
$vm=Get-VM -Id $Id
$dir=Join-Path (Split-Path $PSScriptRoot) ".test/$($vm.Name)"
if($vm.Name -notmatch '^gpupv-test-[a-f0-9]{32}$' -or (Get-Content "$dir/vm-id.txt") -ne $Id){throw 'Test VM ownership mismatch'}
$deadline=(Get-Date).AddMinutes(40)
while($true){
    try{Start-VM -VM $vm;return}catch{
        if($_.Exception.Message -notmatch '0x8007000[Ee]|0x800705[Aa][Aa]|insufficient.*memory|内存不足|内存资源不足' -or (Get-Date) -ge $deadline){throw}
        Start-Sleep -Seconds 15
    }
}
