# S:\rm9\dispinstall.ps1 (SYSTEM, from run.cmd): put the RM9 display-only miniport (rm9disp.sys, 120 Hz VSyncFreq) on the display adapter node ROOT\BasicDisplay\0000, or take it off again (-Revert).
#   package on the ESP: S:\rm9\disp\{rm9disp.sys,rm9disp.inf,rm9disp.cat}.   log: C:\rm9\disp\install.log
param([switch]$Revert, [string]$Src = 'S:\rm9\disp')
$d = 'C:\rm9\disp'
New-Item -ItemType Directory -Force $d | Out-Null
function W($m) {
    $fs = New-Object IO.FileStream("$d\install.log", [IO.FileMode]::Append, [IO.FileAccess]::Write, [IO.FileShare]::ReadWrite, 4096, [IO.FileOptions]::WriteThrough)
    $b = [Text.Encoding]::ASCII.GetBytes("$(Get-Date -Format 'HH:mm:ss') $m`r`n"); $fs.Write($b, 0, $b.Length); $fs.Dispose()
}
function Our-Published {
    $o = & pnputil /enum-drivers 2>&1 | Out-String
    $r = @()
    foreach ($blk in ($o -split "(?:\r?\n){2,}")) {
        if ($blk -match 'rm9disp\.inf' -and $blk -match '(oem\d+\.inf)') { $r += $Matches[1] }
    }
    $r
}
if ($Revert) {
    W "revert requested"
    foreach ($oem in (Our-Published)) { W "delete-driver $oem : $(& pnputil /delete-driver $oem /uninstall /force 2>&1 | Out-String)" }
    Remove-Item "$d\installed.flag" -Force -ErrorAction SilentlyContinue
    Remove-Item "$d\trial.flag","$d\ok.flag" -Force -ErrorAction SilentlyContinue
    & pnputil /scan-devices | Out-Null
    W "revert done"
    return
}
if (Test-Path "S:\rm9\disp_clear.flag") { Remove-Item "$d\failed.flag" -Force -ErrorAction SilentlyContinue; W "failed.flag cleared (disp_clear.flag)" }
if (Test-Path "$d\failed.flag") { W "failed.flag present - not installing (push disp_clear.flag to allow it again)"; return }
if (Test-Path "$d\installed.flag") { W "already installed (flag) - nothing to do"; return }
W "install start"
foreach ($f in 'rm9disp.sys', 'rm9disp.inf', 'rm9disp.cat') { if ($Src -ne $d) { Copy-Item ("$Src\$f") ("$d\$f") -Force } }
W ("added: " + (& pnputil /add-driver "$d\rm9disp.inf" 2>&1 | Out-String).Trim())
Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
public static class Newdev {
  [DllImport("newdev.dll", SetLastError = true, CharSet = CharSet.Unicode)]
  public static extern bool UpdateDriverForPlugAndPlayDevicesW(IntPtr hwnd, string hwid, string inf, uint flags, out bool reboot);
}
'@
$reboot = $false
$ok = [Newdev]::UpdateDriverForPlugAndPlayDevicesW([IntPtr]::Zero, 'ROOT\BasicDisplay', "$d\rm9disp.inf", 1, [ref]$reboot)
W "UpdateDriverForPlugAndPlayDevices ok=$ok err=$([Runtime.InteropServices.Marshal]::GetLastWin32Error()) reboot=$reboot"
if ($ok) { 'installed' | Out-File "$d\installed.flag" -Encoding ascii }
if ($ok) { Remove-Item "$d\ok.flag" -Force -ErrorAction SilentlyContinue; [IO.File]::WriteAllText("$d\trial.flag", '0') }
W ("device: " + (& pnputil /enum-devices /instanceid 'ROOT\BasicDisplay\0000' 2>&1 | Out-String).Trim())
W "install end"
