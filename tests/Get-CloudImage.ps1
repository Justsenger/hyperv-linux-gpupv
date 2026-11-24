param([Parameter(Mandatory)][ValidateSet('ubuntu-22.04','ubuntu-24.04','debian-12','debian-13','fedora-44','rocky-9','arch','leap-15.6','alpine-3.23')][string]$Target)
$ErrorActionPreference='Stop'
switch ($Target){
    'ubuntu-22.04' {$base='https://cloud-images.ubuntu.com/releases/jammy/release';$file='ubuntu-22.04-server-cloudimg-amd64.img';$sum='SHA256SUMS'}
    'ubuntu-24.04' {$base='https://cloud-images.ubuntu.com/releases/noble/release';$file='ubuntu-24.04-server-cloudimg-amd64.img';$sum='SHA256SUMS'}
    'debian-12' {$base='https://cloud.debian.org/images/cloud/bookworm/latest';$file='debian-12-generic-amd64.qcow2';$sum='SHA512SUMS'}
    'debian-13' {$base='https://cloud.debian.org/images/cloud/trixie/latest';$file='debian-13-generic-amd64.qcow2';$sum='SHA512SUMS'}
    'fedora-44' {$base='https://dl.fedoraproject.org/pub/fedora/linux/releases/44/Cloud/x86_64/images';$file='Fedora-Cloud-Base-Generic-44-1.7.x86_64.qcow2';$sum='Fedora-Cloud-44-1.7-x86_64-CHECKSUM'}
    'rocky-9' {$base='https://dl.rockylinux.org/pub/rocky/9/images/x86_64';$file='Rocky-9-GenericCloud-Base.latest.x86_64.qcow2';$sum="$file.CHECKSUM"}
    'arch' {$base='https://geo.mirror.pkgbuild.com/images/latest';$file='Arch-Linux-x86_64-cloudimg.qcow2';$sum="$file.SHA256"}
    'leap-15.6' {$base='https://download.opensuse.org/repositories/Cloud:/Images:/Leap_15.6/images';$file='openSUSE-Leap-15.6.x86_64-NoCloud.qcow2';$sum="$file.sha256"}
    'alpine-3.23' {$base='https://dl-4.alpinelinux.org/alpine/v3.23/releases/cloud';$file='nocloud_alpine-3.23.4-x86_64-uefi-cloudinit-r0.qcow2';$sum="$file.sha512"}
}
$dir=New-Item -Type Directory -Force (Join-Path (Split-Path $PSScriptRoot) '.test/images')
$lines=curl.exe -fsSL --retry 3 --max-time 60 "$base/$sum"
if($LASTEXITCODE){throw "Cannot retrieve $base/$sum"}
$escaped=[regex]::Escape($file)
$hashes=@(foreach($line in $lines){
    if($line -match "^([a-f0-9]{64}|[a-f0-9]{128})\s+\*?$escaped\s*$"){ $Matches[1] }
    elseif($line -match "^SHA(?:256|512)\s*\($escaped\)\s*=\s*([a-f0-9]{64}|[a-f0-9]{128})\s*$"){$Matches[1]}
    elseif($sum.StartsWith($file) -and $line -match '^([a-f0-9]{64}|[a-f0-9]{128})\s*$'){$Matches[1]}
})
if($hashes.Count -ne 1){throw "Cannot identify checksum for $file"}
$expected=$hashes[0]
$algorithm=if($expected.Length -eq 128){'SHA512'}else{'SHA256'}
$dest=Join-Path $dir "gpupv-test-$Target-$($expected.Substring(0,16)).img"
if(!(Test-Path -LiteralPath $dest)){
    $tmp="$dest.$([guid]::NewGuid()).part"
    try{
        curl.exe -fsSL --retry 3 --max-time 1800 "$base/$file" -o $tmp
        if($LASTEXITCODE -or (Get-FileHash -Algorithm $algorithm -LiteralPath $tmp).Hash -ne $expected){throw "Image download or checksum failed for $file"}
        [IO.File]::Move($tmp,$dest)
    }finally{if(Test-Path -LiteralPath $tmp){Remove-Item -LiteralPath $tmp}}
}
if((Get-FileHash -Algorithm $algorithm -LiteralPath $dest).Hash -ne $expected){throw "Cached image checksum failed"}
[pscustomobject]@{Image=$dest;Sha256=(Get-FileHash -LiteralPath $dest).Hash;Source="$base/$file";ChecksumSource="$base/$sum"}


