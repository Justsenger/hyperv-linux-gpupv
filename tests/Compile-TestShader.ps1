# Build the project's HLSL as DXIL using the Windows SDK compiler.
param([string]$Compiler)
$ErrorActionPreference='Stop'
if(!$Compiler){
    $Compiler=(Get-Command dxc.exe -ErrorAction SilentlyContinue).Source
    if(!$Compiler){
        $kit=Join-Path ${env:ProgramFiles(x86)} 'Windows Kits/10/bin'
        $Compiler=(Get-ChildItem "$kit/*/x64/dxc.exe" | Sort-Object { [version]$_.Directory.Parent.Name } -Descending | Select-Object -First 1).FullName
    }
}
if(!$Compiler){throw 'Install the Windows SDK or specify -Compiler with the path to dxc.exe'}
$guest=Join-Path (Split-Path $PSScriptRoot) guest
$temp=[IO.Path]::GetTempFileName()
try {
    & $Compiler -T cs_6_0 -E main -O3 -Qstrip_debug -Fo $temp "$guest/intel-compute.hlsl"
    if($LASTEXITCODE){throw "dxc exited with $LASTEXITCODE"}
    $data=[IO.File]::ReadAllBytes($temp)
} finally { Remove-Item -LiteralPath $temp }
$lines=for($i=0;$i -lt $data.Length;$i+=16){
    ($data[$i..([Math]::Min($i+15,$data.Length-1))] | ForEach-Object {'0x{0:x2}' -f $_}) -join ', '
}
[IO.File]::WriteAllText("$guest/intel-compute.inc",($lines -join ",`n")+"`n")
