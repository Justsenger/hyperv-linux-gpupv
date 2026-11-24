# Read only CopyFiles sections that target the Linux runtime directory.
param([Parameter(Mandatory)][string]$Inf,[ValidateSet('x86_64','aarch64')][string]$Arch)
if(!$Arch){
    $Arch = switch ([Runtime.InteropServices.RuntimeInformation]::OSArchitecture.ToString()) {
        'X64' {'x86_64'}
        'Arm64' {'aarch64'}
        default {throw 'Unsupported host architecture'}
    }
}
$decoration = if($Arch -eq 'aarch64'){'arm64'}else{'amd64'}
function Test-ApplicableSection([string]$Name){
    if($Name -match '(?:^|\.)(?:NT)?(amd64|arm64|x86|arm)(?:\.|$)'){return $Matches[1] -eq $decoration}
    return $true
}
$sections=@{}
$current=''
foreach($raw in [IO.File]::ReadLines($Inf)){
    $line=($raw -split ';',2)[0].Trim()
    if($line -match '^\[([^\]]+)\]$'){
        $current=$Matches[1]
        if(!$sections.ContainsKey($current)){$sections[$current]=[Collections.Generic.List[string]]::new()}
    }elseif($current -and $line){$sections[$current].Add($line)}
}
$aliases=@{}
foreach($section in @($sections.Keys | Where-Object {$_ -match '^DestinationDirs(?:\.|$)'})){
    if(!(Test-ApplicableSection $section)){continue}
    foreach($entry in $sections[$section]){
        if($entry -notmatch '^([^=]+?)\s*=\s*11\s*,\s*"?lxss\\lib"?\s*$'){continue}
        $copy=$Matches[1].Trim()
        if(!(Test-ApplicableSection $copy)){continue}
        foreach($row in $sections[$copy]){
            $parts=$row.Split(',')
            $dst=$parts[0].Trim(' ','"')
            $src=if($parts.Count -gt 1 -and $parts[1].Trim()){$parts[1].Trim(' ','"')}else{$dst}
            if($src -notmatch '^[a-z0-9_+.-]+$' -or $dst -notmatch '^[a-z0-9_+.-]+$' -or $src -in '.','..' -or $dst -in '.','..'){throw "Unsupported INF filename: $row"}
            if($aliases.ContainsKey($dst) -and $aliases[$dst] -ne $src){throw "Ambiguous Linux driver file $dst"}
            $aliases[$dst]=$src
        }
    }
}
$aliases

