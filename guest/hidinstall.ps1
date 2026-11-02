# C:\rm9\link\hidinstall.ps1 (SYSTEM): create the root-enumerated device ROOT\RM9HID (once) and install the driver package from -Src (rm9hid.inf/.sys/.cat).  -Remove: take it off again.
param([string]$Src = 'C:\rm9\hid', [switch]$Remove)
Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
public static class Hidi {
  [StructLayout(LayoutKind.Sequential)] public struct SP_DEVINFO_DATA { public int cbSize; public Guid ClassGuid; public int DevInst; public IntPtr Reserved; }
  [DllImport("setupapi.dll", SetLastError = true)] public static extern IntPtr SetupDiCreateDeviceInfoList(ref Guid g, IntPtr h);
  [DllImport("setupapi.dll", SetLastError = true, CharSet = CharSet.Unicode)] public static extern bool SetupDiCreateDeviceInfoW(IntPtr set, string name, ref Guid g, string desc, IntPtr h, uint flags, ref SP_DEVINFO_DATA d);
  [DllImport("setupapi.dll", SetLastError = true, CharSet = CharSet.Unicode)] public static extern bool SetupDiSetDeviceRegistryPropertyW(IntPtr set, ref SP_DEVINFO_DATA d, uint prop, byte[] buf, int len);
  [DllImport("setupapi.dll", SetLastError = true)] public static extern bool SetupDiCallClassInstaller(uint fn, IntPtr set, ref SP_DEVINFO_DATA d);
  [DllImport("setupapi.dll", SetLastError = true)] public static extern bool SetupDiDestroyDeviceInfoList(IntPtr set);
  [DllImport("newdev.dll", SetLastError = true, CharSet = CharSet.Unicode)] public static extern bool UpdateDriverForPlugAndPlayDevicesW(IntPtr hwnd, string hwid, string inf, uint flags, out bool reboot);
}
'@
$log = 'C:\rm9\hid\install.log'
New-Item -ItemType Directory -Force C:\rm9\hid | Out-Null
function W($m) { "$(Get-Date -Format 'HH:mm:ss') $m" | Out-File -Append -Encoding ascii $log }
if ($Remove) {
    foreach ($d in (Get-PnpDevice -ErrorAction SilentlyContinue | Where-Object { $_.FriendlyName -like 'RM9 Virtual HID*' -and $_.InstanceId -like 'ROOT\*' })) { W "remove $($d.InstanceId)"; pnputil /remove-device $d.InstanceId | Out-Null }
    foreach ($blk in ((pnputil /enum-drivers | Out-String) -split "(?:\r?\n){2,}")) { if ($blk -match 'rm9hid\.inf' -and $blk -match '(oem\d+\.inf)') { W "delete $($Matches[1])"; pnputil /delete-driver $Matches[1] /uninstall /force | Out-Null } }
    return
}
$exists = Get-PnpDevice -ErrorAction SilentlyContinue | Where-Object { $_.HardwareID -contains 'ROOT\RM9HID' }
if (-not $exists) {
    $g = [Guid]'4d36e97d-e325-11ce-bfc1-08002be10318'
    $set = [Hidi]::SetupDiCreateDeviceInfoList([ref]$g, [IntPtr]::Zero)
    $d = New-Object Hidi+SP_DEVINFO_DATA; $d.cbSize = [Runtime.InteropServices.Marshal]::SizeOf($d)
    $ok = [Hidi]::SetupDiCreateDeviceInfoW($set, 'RM9HID', [ref]$g, 'RM9 Virtual HID Touch Screen', [IntPtr]::Zero, 1, [ref]$d)
    W "CreateDeviceInfo ok=$ok err=$([Runtime.InteropServices.Marshal]::GetLastWin32Error())"
    $hw = [Text.Encoding]::Unicode.GetBytes("ROOT\RM9HID`0`0")
    $ok = [Hidi]::SetupDiSetDeviceRegistryPropertyW($set, [ref]$d, 1, $hw, $hw.Length)
    W "SetHardwareId ok=$ok"
    $ok = [Hidi]::SetupDiCallClassInstaller(0x19, $set, [ref]$d)
    W "RegisterDevice ok=$ok err=$([Runtime.InteropServices.Marshal]::GetLastWin32Error())"
    [void][Hidi]::SetupDiDestroyDeviceInfoList($set)
}
W ("pnputil add: " + ((& pnputil /add-driver "$Src\rm9hid.inf" 2>&1) | Out-String).Trim())
$reboot = $false
$ok = [Hidi]::UpdateDriverForPlugAndPlayDevicesW([IntPtr]::Zero, 'ROOT\RM9HID', "$Src\rm9hid.inf", 1, [ref]$reboot)
W "UpdateDriver ok=$ok err=$([Runtime.InteropServices.Marshal]::GetLastWin32Error()) reboot=$reboot"
W ((Get-PnpDevice -ErrorAction SilentlyContinue | Where-Object { $_.FriendlyName -like '*RM9 Virtual HID*' -or $_.InstanceId -like 'HID\VHF*' } | Format-Table Class, FriendlyName, Status, InstanceId -AutoSize | Out-String))
