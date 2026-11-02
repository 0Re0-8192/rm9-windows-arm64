# C:\rm9\link\irqinstall.ps1 (SYSTEM): install the rm9irq driver package from -Src (rm9irq.inf/.sys/.cat).
#   default: create the root-enumerated device ROOT\RM9IRQ (once) and bind it (old design; its IRQConfig resources stay untranslated on ARM64, NEXT.md 0ba).
#   -Acpi:   bind the ACPI device ACPI\RM9I0001 (DSDT of Mu-pcie-rp5, _CRS interrupts 800..811); a leftover ROOT\RM9IRQ device and the old packages are removed first.   -Remove: take everything off again.
param([string]$Src = 'C:\rm9\irq', [switch]$Remove, [switch]$Acpi)
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
$log = 'C:\rm9\irq\install.log'
New-Item -ItemType Directory -Force C:\rm9\irq | Out-Null
function W($m) { "$(Get-Date -Format 'HH:mm:ss') $m" | Out-File -Append -Encoding ascii $log }
function RemoveOld {
    foreach ($d in (Get-PnpDevice -ErrorAction SilentlyContinue | Where-Object { $_.InstanceId -like 'ROOT\RM9IRQ*' })) { W "remove $($d.InstanceId)"; pnputil /remove-device $d.InstanceId | Out-Null }
    foreach ($blk in ((pnputil /enum-drivers | Out-String) -split "(?:\r?\n){2,}")) { if ($blk -match 'rm9irq\.inf' -and $blk -match '(oem\d+\.inf)') { W "delete $($Matches[1])"; pnputil /delete-driver $Matches[1] /uninstall /force | Out-Null } }
}
if ($Remove) { RemoveOld; return }
if ($Acpi) {
    RemoveOld
    W ("pnputil add: " + ((& pnputil /add-driver "$Src\rm9irq.inf" /install 2>&1) | Out-String).Trim())
    $reboot = $false
    $ok = [Hidi]::UpdateDriverForPlugAndPlayDevicesW([IntPtr]::Zero, 'ACPI\RM9I0001', "$Src\rm9irq.inf", 1, [ref]$reboot)
    W "UpdateDriver ok=$ok err=$([Runtime.InteropServices.Marshal]::GetLastWin32Error()) reboot=$reboot"
    W ((Get-PnpDevice -ErrorAction SilentlyContinue | Where-Object { $_.InstanceId -like 'ACPI\RM9I0001*' -or $_.FriendlyName -like '*RM9 Wi-Fi SPI*' } | Format-List Class, FriendlyName, Status, Problem, InstanceId | Out-String))
    return
}
$exists = Get-PnpDevice -ErrorAction SilentlyContinue | Where-Object { $_.HardwareID -contains 'ROOT\RM9IRQ' }
if (-not $exists) {
    $g = [Guid]'4d36e97d-e325-11ce-bfc1-08002be10318'
    $set = [Hidi]::SetupDiCreateDeviceInfoList([ref]$g, [IntPtr]::Zero)
    $d = New-Object Hidi+SP_DEVINFO_DATA; $d.cbSize = [Runtime.InteropServices.Marshal]::SizeOf($d)
    $ok = [Hidi]::SetupDiCreateDeviceInfoW($set, 'RM9IRQ', [ref]$g, 'RM9 Wi-Fi SPI Interrupts', [IntPtr]::Zero, 1, [ref]$d)
    W "CreateDeviceInfo ok=$ok err=$([Runtime.InteropServices.Marshal]::GetLastWin32Error())"
    $hw = [Text.Encoding]::Unicode.GetBytes("ROOT\RM9IRQ`0`0")
    $ok = [Hidi]::SetupDiSetDeviceRegistryPropertyW($set, [ref]$d, 1, $hw, $hw.Length)
    W "SetHardwareId ok=$ok"
    $ok = [Hidi]::SetupDiCallClassInstaller(0x19, $set, [ref]$d)
    W "RegisterDevice ok=$ok err=$([Runtime.InteropServices.Marshal]::GetLastWin32Error())"
    [void][Hidi]::SetupDiDestroyDeviceInfoList($set)
}
W ("pnputil add: " + ((& pnputil /add-driver "$Src\rm9irq.inf" 2>&1) | Out-String).Trim())
$reboot = $false
$ok = [Hidi]::UpdateDriverForPlugAndPlayDevicesW([IntPtr]::Zero, 'ROOT\RM9IRQ', "$Src\rm9irq.inf", 1, [ref]$reboot)
W "UpdateDriver ok=$ok err=$([Runtime.InteropServices.Marshal]::GetLastWin32Error()) reboot=$reboot"
W ((Get-PnpDevice -ErrorAction SilentlyContinue | Where-Object { $_.FriendlyName -like '*RM9 Wi-Fi SPI*' -or $_.InstanceId -like 'HID\VHF*' } | Format-Table Class, FriendlyName, Status, InstanceId -AutoSize | Out-String))
