# C:\rm9\link\touchhid.ps1 (SYSTEM task rm9touchhid): feed the virtual HID touch screen (rm9hid.sys) from touch.cur (written by touchpoll.ps1); replaces touchinject.ps1.
# Windows "hybrid mode" touch reports: one report per contact { id=1, tip, contact id, X(16), Y(16), scan time(16), contact count }; contact count is the number of contacts in the frame in the first report, 0 in the rest.
#   -Test: send a synthetic two-finger drag (checks the HID path without touching the panel) and exit.
param([int]$Seconds = 8640000, [string]$Cur = 'C:\Users\Public\rm9shot\touch.cur', [switch]$Test, [int]$TapX = -1, [int]$TapY = -1)
Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
using Microsoft.Win32.SafeHandles;
public static class HidFeed {
  [DllImport("kernel32.dll", CharSet = CharSet.Unicode, SetLastError = true)] static extern SafeFileHandle CreateFileW(string n, uint a, uint s, IntPtr sa, uint d, uint f, IntPtr t);
  [DllImport("kernel32.dll", SetLastError = true)] static extern bool DeviceIoControl(SafeFileHandle h, uint c, byte[] i, int il, byte[] o, int ol, out int r, IntPtr ov);
  static SafeFileHandle H;
  public static bool Open() { H = CreateFileW(@"\\.\Rm9Hid", 0xC0000000, 3, IntPtr.Zero, 3, 0, IntPtr.Zero); return !H.IsInvalid; }
  public static int Send(byte[] rpt) { int r; return DeviceIoControl(H, 0x22A400, rpt, rpt.Length, null, 0, out r, IntPtr.Zero) ? 0 : Marshal.GetLastWin32Error(); }
  public static int[] Stats() { byte[] o = new byte[8]; int r; DeviceIoControl(H, 0x226404, null, 0, o, 8, out r, IntPtr.Zero); return new int[] { BitConverter.ToInt32(o, 0), BitConverter.ToInt32(o, 4) }; }
  public static byte[] One(int tip, int id, int x, int y, int scan, int count) {
    return new byte[] { 1, (byte)tip, (byte)id, (byte)(x & 255), (byte)((x >> 8) & 255), (byte)(y & 255), (byte)((y >> 8) & 255), (byte)(scan & 255), (byte)((scan >> 8) & 255), (byte)count };
  }
}
'@
$log = 'C:\rm9\link\touchhid.txt'
function L($m) { "$(Get-Date -Format 'HH:mm:ss.fff') $m" | Out-File -Append -Encoding ascii $log }
for ($i = 0; $i -lt 30 -and -not [HidFeed]::Open(); $i++) { Start-Sleep 2 }
if ($i -ge 30) { L 'cannot open Rm9Hid'; if ($Test) { 'NOOPEN' }; return }
L 'opened Rm9Hid'
# send one frame: $now = ordered hashtable id -> @(x,y) (contacts down), $prev = same for the previous frame
function Frame($now, $prev, $scan) {
    $errs = 0
    $list = New-Object System.Collections.ArrayList
    foreach ($id in $now.Keys) { [void]$list.Add(@(1, $id, $now[$id][0], $now[$id][1])) }
    foreach ($id in $prev.Keys) { if (-not $now.Contains($id)) { [void]$list.Add(@(0, $id, $prev[$id][0], $prev[$id][1])) } }
    for ($k = 0; $k -lt $list.Count; $k++) {
        $c = $list[$k]
        $errs += [HidFeed]::Send([HidFeed]::One($c[0], $c[1], $c[2], $c[3], $scan, $(if ($k -eq 0) { $list.Count } else { 0 })))
    }
    return $errs
}
if ($TapX -ge 0) {
    $scan = 1000; $errs = 0; $prev = @{}
    for ($s = 0; $s -lt 10; $s++) { $scan += 83; $now = @{}; $now[1] = @($TapX, $TapY); $errs += Frame $now $prev $scan; $prev = $now; Start-Sleep -Milliseconds 20 }
    $errs += Frame @{} $prev ($scan + 83)
    'tap sent errs=' + $errs
    return
}
if ($Test) {
    $scan = 0; $errs = 0; $prev = @{}
    for ($s = 0; $s -le 20; $s++) {
        $scan += 83
        $now = @{}
        $now[1] = @((3000 + 400 * $s), (8000 + 300 * $s))
        $now[2] = @((12000 - 300 * $s), (20000 + 500 * $s))
        $errs += Frame $now $prev $scan; $prev = $now; Start-Sleep -Milliseconds 16
    }
    $errs += Frame (@{}) $prev ($scan + 83)
    "test done errs=$errs stats(reports,failed)=" + ([HidFeed]::Stats() -join ',')
    return
}
$last = 0; $scan = 0; $prev = @{}; $sent = 0
$sw = [Diagnostics.Stopwatch]::StartNew()
while ($sw.Elapsed.TotalSeconds -lt $Seconds) {
    $line = $null
    try { $line = [IO.File]::ReadAllText($Cur) } catch {}
    if ($line -and $line.EndsWith(';')) {
        $p = $line.Split(';'); $seq = [uint32]$p[0]
        if ($seq -ne $last) {
            $last = $seq; $cnt = [Math]::Min([int]$p[1], 5); $now = @{}
            for ($i = 0; $i -lt $cnt; $i++) { $q = $p[2 + $i].Split(','); $now[[int]$q[0]] = @([int][double]$q[1], [int][double]$q[2]) }
            if ($now.Count -gt 0 -or $prev.Count -gt 0) {
                $scan = ($scan + 83) -band 0xFFFF
                $e = Frame $now $prev $scan; $sent++
                if ($e -ne 0 -and ($sent % 100) -eq 1) { L "send err=$e" }
            }
            $prev = $now
        }
    }
    Start-Sleep -Milliseconds 2
}
