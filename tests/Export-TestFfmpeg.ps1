param([Parameter(Mandatory)][guid]$Id,[Parameter(Mandatory)][string]$Key,[Parameter(Mandatory)][string]$Output,[switch]$IntelVideo)
$ErrorActionPreference='Stop'
$root=Split-Path $PSScriptRoot
$vm=Get-VM -Id $Id
$dir=Join-Path $root ".test/$($vm.Name)"
if($vm.Name -notmatch '^gpupv-test-[0-9a-f]{32}$' -or (Get-Content "$dir/vm-id.txt") -ne $Id){throw 'Guest ownership mismatch'}
$ip=(Resolve-DnsName "$($vm.Name).mshome.net" -Type A).IPAddress
$ss=@('-o','ConnectTimeout=6','-o',"HostKeyAlias=$Id",'-o',"UserKnownHostsFile=$dir/known_hosts",'-o','StrictHostKeyChecking=yes','-i',$Key,"tester@$ip")
$remote=@'
set -eu
test "$(hostname)" = VMNAME
. /etc/os-release
test "$ID:$VERSION_ID" = ubuntu:24.04
d=$(mktemp -d)
trap 'rm -rf "$d"' EXIT
mkdir "$d/lib"
cp /usr/bin/ffmpeg "$d/ffmpeg.bin"
ldd /usr/bin/ffmpeg | awk '/=> \// {print $3} /^[[:space:]]*\// {print $1}' | sort -u > "$d/files"
while read -r f; do case "$f" in /lib/*|/lib64/*|/usr/lib/*) ;; *) exit 1;; esac; case "$f" in */wsl/*|*libcuda*|*libd3d12*|*libdxcore*) exit 1;; esac; cp -L "$f" "$d/lib/"; done < "$d/files"
# These compatibility DSOs are requested by the vendor driver at dlopen time.
for name in libdl.so.2 libpthread.so.0 librt.so.1 libutil.so.1; do
    cp -L "/usr/lib/x86_64-linux-gnu/$name" "$d/lib/$name"
done
dpkg-query -W ffmpeg libc6 > "$d/packages"
cat > "$d/ffmpeg" <<'SH'
#!/bin/sh
prefix=$(dirname "$(readlink -f "$0")")
exec "$prefix/lib/ld-linux-x86-64.so.2" --library-path "$prefix/lib:/usr/lib/wsl/lib" "$prefix/ffmpeg.bin" "$@"
SH
chmod +x "$d/ffmpeg"
if [ "INCLUDE_INTEL" = yes ]; then
    driver=/usr/lib/x86_64-linux-gnu/dri/d3d12_drv_video.so
    cp -L "$driver" "$d/lib/d3d12_drv_video.so"
    cp /usr/bin/vainfo "$d/vainfo.bin"
    for binary in "$driver" /usr/bin/vainfo; do
        ldd "$binary" | awk '/=> \// {print $3} /^[[:space:]]*\// {print $1}' | sort -u > "$d/va-files"
        while read -r f; do
            case "$f" in */wsl/*|*libcuda*|*libd3d12*|*libdxcore*) exit 1;; /lib/*|/lib64/*|/usr/lib/*) ;; *) exit 1;; esac
            cp -L "$f" "$d/lib/"
        done < "$d/va-files"
    done
    sed 's/"$prefix\/ffmpeg.bin"/"$prefix\/vainfo.bin"/' "$d/ffmpeg" > "$d/vainfo"
    chmod +x "$d/vainfo"
    dpkg-query -W vainfo mesa-va-drivers mesa-libgallium libva2 libllvm20 >> "$d/packages"
fi
"$d/ffmpeg" -hide_banner -encoders | grep -q h264_nvenc
"$d/ffmpeg" -hide_banner -decoders | grep -q h264_cuvid
tar -czf - -C "$d" .
'@
$dest=$ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($Output)
$part="$dest.$([guid]::NewGuid()).part"
try{
    $include=if($IntelVideo){'yes'}else{'no'}
    ssh.exe @ss ($remote.Replace('VMNAME',$vm.Name).Replace('INCLUDE_INTEL',$include).Replace("`r","")) > $part
    if($LASTEXITCODE){throw 'FFmpeg fixture capture failed'}
    [IO.File]::Move($part,$dest)
}finally{if(Test-Path -LiteralPath $part){Remove-Item -LiteralPath $part}}
Get-FileHash -LiteralPath $dest

