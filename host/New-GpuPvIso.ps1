param([Parameter(Mandatory)][string]$Source,[Parameter(Mandatory)][string]$Output,[string]$Label='GPUPV')
$ErrorActionPreference='Stop'
if (-not ('GpuPvIsoWriter' -as [type])) {
Add-Type @'
using System;
using System.IO;
using System.Runtime.InteropServices;
using System.Runtime.InteropServices.ComTypes;
public static class GpuPvIsoWriter {
    public static void Save(object obj, string path) {
        var stream = (IStream)obj;
        var count = Marshal.AllocHGlobal(4);
        try {
            using (var output = new FileStream(path, FileMode.CreateNew, FileAccess.Write)) {
                var buffer = new byte[65536];
                while (true) {
                    stream.Read(buffer, buffer.Length, count);
                    int n = Marshal.ReadInt32(count);
                    if (n == 0) break;
                    output.Write(buffer, 0, n);
                }
            }
        } finally { Marshal.FreeHGlobal(count); }
    }
}
'@
}
$fs=New-Object -ComObject IMAPI2FS.MsftFileSystemImage
$fs.ChooseImageDefaultsForMediaType(12)
$fs.FileSystemsToCreate=if($Label -eq 'cidata'){3}else{4}
$fs.VolumeName=$Label
$fs.Root.AddTree((Resolve-Path -LiteralPath $Source).Path,$false)
$dest=$ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($Output)
if(Test-Path -LiteralPath $dest){throw "Output already exists: $dest"}
$partial="$dest.$([guid]::NewGuid()).part"
try{
    $result=$fs.CreateResultImage()
    $imageStream=$result.ImageStream
    try{[GpuPvIsoWriter]::Save($imageStream,$partial)}finally{
        [void][Runtime.InteropServices.Marshal]::FinalReleaseComObject($imageStream)
        [void][Runtime.InteropServices.Marshal]::FinalReleaseComObject($result)
    }
    [IO.File]::Move($partial,$dest)
}finally{
    [void][Runtime.InteropServices.Marshal]::FinalReleaseComObject($fs)
    [GC]::Collect()
    [GC]::WaitForPendingFinalizers()
    if(Test-Path -LiteralPath $partial){Remove-Item -LiteralPath $partial}
}


