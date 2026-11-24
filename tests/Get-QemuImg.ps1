# Developer-only helper for creating test VHDX files on Windows.
param([string]$SevenZip="$env:ProgramFiles\7-Zip\7z.exe")
$ErrorActionPreference='Stop'
if(!(Test-Path -LiteralPath $SevenZip)){throw 'Specify -SevenZip with the path to 7z.exe'}
$dir=New-Item -Type Directory -Force (Join-Path (Split-Path $PSScriptRoot) '.tools')
$name='qemu-w64-setup-20260811.exe'
$expected='F98A8AEB5F7FAEA9765B6DEE28316C266CD179D80354A2FED8E50176F9A2E59F'
$exe=Join-Path $dir $name
if(!(Test-Path -LiteralPath $exe)){
    $tmp="$exe.$([guid]::NewGuid()).part"
    try{
        curl.exe -fsSL --max-time 600 "https://qemu.weilnetz.de/w64/$name" -o $tmp
        if($LASTEXITCODE -or (Get-FileHash $tmp).Hash -ne $expected){throw 'QEMU download or checksum failed'}
        [IO.File]::Move($tmp,$exe)
    }finally{if(Test-Path -LiteralPath $tmp){Remove-Item -LiteralPath $tmp}}
}
if((Get-FileHash $exe).Hash -ne $expected){throw 'QEMU installer checksum mismatch'}
$dest=Join-Path $dir ('qemu-img-'+[guid]::NewGuid().ToString('N'))
& $SevenZip x $exe "-o$dest" 'qemu-img.exe' '*.dll' 'COPYING*' -y | Out-Null
if($LASTEXITCODE){throw 'Cannot extract QEMU'}
$tool=Join-Path $dest qemu-img.exe
& $tool --version | Out-Host
if($LASTEXITCODE){throw 'qemu-img startup failed'}
$tool

