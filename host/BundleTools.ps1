function Assert-BundleArchitecture($Manifest, [string]$ExpectedArch) {
    if ($Manifest.schemaVersion -ne 1 -or $Manifest.arch -cne $ExpectedArch) {
        throw "部署包架构 $($Manifest.arch) 或版本格式不匹配。请选择 $ExpectedArch 包。"
    }
}

function Add-DriverFile([string]$Source, [string]$Directory, [string]$Name) {
    if ($Name -notmatch '^[\w+.-]+$' -or $Name -in '.', '..') { throw "Invalid alias $Name" }
    $dst=Join-Path $Directory $Name
    if (Test-Path -LiteralPath $dst) {
        if ((Get-FileHash -LiteralPath $dst).Hash -ne (Get-FileHash -LiteralPath $Source).Hash) {
            throw "显卡运行库同名内容冲突: $Name"
        }
    } else { Copy-Item -LiteralPath $Source -Destination $dst }
}

function Read-BundleMetadata($Zip, [string]$ExpectedArch, $PinnedFiles) {
    function Read-JsonEntry($name) {
        $entry=$Zip.GetEntry($name)
        if(!$entry){throw "Missing bundle member $name"}
        $reader=[IO.StreamReader]::new($entry.Open())
        try { $reader.ReadToEnd()|ConvertFrom-Json -AsHashtable -NoEnumerate } finally { $reader.Dispose() }
    }
    function Assert-Member($name,$hash,$types) {
        $entry=$Zip.GetEntry($name)
        if(!$entry -or $hash -notmatch '^[0-9a-f]{64}$'){throw "Invalid bundle member $name"}
        $stream=$entry.Open()
        try {
            $header=[byte[]]::new(64)
            $stream.ReadExactly($header)
            $machine=if($ExpectedArch -eq 'aarch64'){183}else{62}
            if([BitConverter]::ToString($header,0,6) -ne '7F-45-4C-46-02-01' -or [BitConverter]::ToUInt16($header,16) -notin $types -or [BitConverter]::ToUInt16($header,18) -ne $machine){throw "Wrong ELF: $name"}
        } finally {$stream.Dispose()}
        $stream=$entry.Open()
        try {if([Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($stream)) -ne $hash){throw "Checksum mismatch: $name"}}
        finally {$stream.Dispose()}
    }
    $meta=Read-JsonEntry 'manifest.json'
    Assert-BundleArchitecture $meta $ExpectedArch
    foreach($file in $PinnedFiles){
        if($meta.libraries[$file.name] -ne $file.sha256){throw "Unknown Microsoft runtime: $($file.name)"}
        Assert-Member "lib/$($file.name)" $file.sha256 @(3)
    }
    Assert-Member 'guest/d3d12-compute' $meta.probeSha256 @(2,3)
    $entries=Read-JsonEntry 'prebuilt/index.json'
    if(!$entries.Count -or (ConvertTo-Json -InputObject $entries -Depth 8 -Compress) -cne (ConvertTo-Json -InputObject $meta.kernels -Depth 8 -Compress)){throw 'Invalid prebuilt index'}
    foreach($entry in $entries){
        if($entry.release -notmatch '^[A-Za-z0-9][A-Za-z0-9.+_-]*$' -or $entry.arch -cne $ExpectedArch -or $entry.name -cne 'dxgkrnl' -or $entry.vermagic.Split(' ')[0] -cne $entry.release){throw 'Invalid module metadata'}
        Assert-Member "prebuilt/$ExpectedArch/$($entry.release)/dxgkrnl.ko" $entry.sha256 @(1)
    }
    return $meta
}


function Get-SelectedGpu($Cards, [string[]]$Ids) {
    $selected = @(foreach ($id in $Ids) {
        $matchesForId = @($Cards | Where-Object { $_.Instance -eq $id -or $_.Pnp -eq $id -or $_.Name -eq $id })
        if ($matchesForId.Count -ne 1) { throw "无法唯一识别 $id，请使用实例路径。" }
        $matchesForId[0]
    })
    if (@($selected.Instance | Sort-Object -Unique).Count -ne $selected.Count) {
        throw 'Duplicate adapter'
    }
    $selected
}
