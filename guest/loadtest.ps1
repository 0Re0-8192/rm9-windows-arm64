# loadtest.ps1 - what does a REAL all-core load do to the temperature with the CPU frequency cap that dbgcap.sys holds?  Phases: idle 20 s, 8 busy threads for 60 s, idle 40 s.
# Every 3 s: hottest TSENS (dbgcap's windowed maximum), each cluster's performance state / frequency (EPSS, read-only), Windows' total CPU load.  Stops the load at once if the SoC reaches 98 C.
# Log: S:\rm9\loadtest.txt (WriteThrough).  Runs after guard.cmd, so a freeze resets the phone within ~31 s.  Nothing is written to the frequency registers here (dbgcap.sys does that).
. S:\rm9\rm9io.ps1
. S:\rm9\dbgcap.ps1
Add-Type -TypeDefinition @'
using System;
using System.Threading;
public static class Burn {
  public static volatile bool Stop;
  public static void Start(int n) {
    Stop = false;
    for (int i = 0; i < n; i++) { Thread t = new Thread(delegate() { double x = 1.0; long k = 0; while (!Stop) { x = x * 1.0000001 + Math.Sqrt(k + 1.0); k++; if (k > 1000000000L) { k = 0; x = 1.0; } } }); t.IsBackground = true; t.Start(); }
  }
}
'@
$fs = New-Object IO.FileStream('S:\rm9\loadtest.txt', [IO.FileMode]::Append, [IO.FileAccess]::Write, [IO.FileShare]::ReadWrite, 4096, [IO.FileOptions]::WriteThrough)
function L($s) { $b = [Text.Encoding]::ASCII.GetBytes(((Get-Date -Format 'HH:mm:ss.fff') + ' ' + $s + "`r`n")); $fs.Write($b, 0, $b.Length); $fs.Flush() }
function Hottest {
    if (-not [DbgCap]::Open()) { return $null }
    $buf = New-Object byte[] 32; $ret = 0
    $code = [Convert]::ToUInt32('8F002820', 16)
    try { $ok = [DbgCap]::DeviceIoControl([DbgCap]::H, $code, $buf, 4, $buf, 32, [ref]$ret, [IntPtr]::Zero) } catch { return $null }
    if (-not $ok) { return $null }
    return [BitConverter]::ToInt32($buf, 4) / 10.0
}
function RdTry([uint64]$a) { for ($k = 0; $k -lt 3; $k++) { try { return (Rm9Read $a 1)[0] } catch { Start-Sleep -Milliseconds 20 } } return $null }
L '=== loadtest start'
if ((Get-Service rm9io -ErrorAction SilentlyContinue).Status -ne 'Running') { Start-Service rm9io -ErrorAction SilentlyContinue; Start-Sleep 1 }
$bases = @(0x17D91000, 0x17D92000, 0x17D93000, 0x17D94000)
$lut = @{}
for ($d = 0; $d -lt 4; $d++) { $lut[$d] = @(); for ($i = 0; $i -lt 40; $i++) { $v = RdTry ([uint64]($bases[$d] + 0x100 + 4 * $i)); if (-not $v -or ($v -band 0xFF) -eq 0) { break }; $lut[$d] += [int](($v -band 0xFF) * 19.2) } }
function Snap([string]$tag) {
    $t = Hottest
    $f = @()
    for ($d = 0; $d -lt 4; $d++) { $p = RdTry ([uint64]($bases[$d] + 0x320)); if ($p -eq $null) { $f += '?' } else { $i = [int]($p -band 0x3F); $f += $(if ($i -lt $lut[$d].Count) { $lut[$d][$i] } else { "idx$i" }) } }
    $c = ''
    try { $c = [int](Get-Counter '\Processor(_Total)\% Processor Time' -ErrorAction Stop).CounterSamples[0].CookedValue } catch { $c = 'n/a' }
    L ('{0} hottest={1}C  MHz dom0..3={2}  cpu={3}%' -f $tag, $t, ($f -join '/'), $c)
    return $t
}
L '--- idle 20 s'
for ($i = 0; $i -lt 7; $i++) { $null = Snap ('idle t=' + ($i * 3)); Start-Sleep 3 }
L '--- 8 busy threads for 60 s'
[Burn]::Start(8)
$maxT = 0
for ($i = 0; $i -lt 20; $i++) {
    $t = Snap ('load t=' + ($i * 3))
    if ($t -ne $null -and $t -gt $maxT) { $maxT = $t }
    if ($t -ne $null -and $t -ge 98) { L 'HOT >= 98 C: load stopped early'; break }
    Start-Sleep 3
}
[Burn]::Stop = $true
L ('--- load stopped, peak hottest=' + $maxT + 'C; idle 40 s')
for ($i = 0; $i -lt 14; $i++) { $null = Snap ('cool t=' + ($i * 3)); Start-Sleep 3 }
L '=== loadtest end'
$fs.Close()
