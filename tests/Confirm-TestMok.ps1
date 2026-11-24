# Enroll a transient guest-generated key only on a locally owned acceptance VM.
param([Parameter(Mandatory)][guid]$Id,[Parameter(Mandatory)][string]$Password)
$ErrorActionPreference='Stop'
$v=Get-VM -Id $Id
$base=Split-Path $PSScriptRoot
if($v.Name -notmatch '^gpupv-test-[a-f0-9]{32}$' -or (Get-Content -LiteralPath "$base/.test/$($v.Name)/vm-id.txt") -ne $Id){throw 'Test VM ownership mismatch'}
$ns='root/virtualization/v2'
$system=Get-CimInstance -Namespace $ns -ClassName Msvm_ComputerSystem -Filter "Name='$Id'"
$service=Get-CimInstance -Namespace $ns -ClassName Msvm_VirtualSystemManagementService
$key=Get-CimInstance -Namespace $ns -ClassName Msvm_Keyboard -Filter "SystemName='$Id'"
function Press([uint32]$Code){
    $r=Invoke-CimMethod -InputObject $key -MethodName TypeKey -Arguments @{KeyCode=$Code}
    if($r.ReturnValue){throw "Guest keyboard failed: $($r.ReturnValue)"}
}
# Hash only the central menu and heading of the 800x600 RGB565 thumbnail.
# Recognize each observed shim screen before sending input.
$menus=[ordered]@{
    management='096f9397fd29800b83fdc1b818dcf90b90df47769c72ac4afc521a9172fac972'
    view='9eefec7bc9fe1f516c2aa282ba1a2a7476c51b847b6d0ce06b6ad58462edd451'
    confirm='5a083fdb9f07fc0c159f0698f92eb218b4ebba2124c56afeb260ba16088beb74'
    password='7080ffa34442f7ce8ea6bc9d47cf7129fcc75904e033b1eba04aa67415e7bff6'
    reboot='a315842bc21ba463d2fe9f0845acd0fa4c101f4a5161fd56984317bdf1c6f6f7'
}
foreach($name in $menus.Keys){
    $end=(Get-Date).AddSeconds(95)
    do{
        Start-Sleep -Milliseconds 600
        $state=Get-CimAssociatedInstance -InputObject $system -Association Msvm_SettingsDefineState -ResultClassName Msvm_VirtualSystemSettingData
        $r=Invoke-CimMethod -InputObject $service -MethodName GetVirtualSystemThumbnailImage -Arguments @{TargetSystem=$state;WidthPixels=[uint16]800;HeightPixels=[uint16]600}
        if($r.ReturnValue -or $r.ImageData.Length -lt 960000){continue}
        $bytes=[byte[]]::new(320*210)
        for($y=0;$y -lt 210;$y++){
            [Array]::Copy($r.ImageData,$r.ImageData.Length-960000+(120+$y)*1600+640,$bytes,$y*320,320)
        }
        $digest=[Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($bytes))
        if($digest -eq $menus[$name]){break}
    }while((Get-Date) -lt $end)
    if($digest -ne $menus[$name]){throw "Unrecognized guest MOK screen ($name, $digest)"}
    Write-Output "$Id confirmed shim menu $name"
    if($name -eq 'password'){
        $r=Invoke-CimMethod -InputObject $key -MethodName TypeText -Arguments @{AsciiText=$Password}
        if($r.ReturnValue){throw 'Guest password input failed'}
    }elseif($name -ne 'reboot'){Press 40}
    Press 13
}
