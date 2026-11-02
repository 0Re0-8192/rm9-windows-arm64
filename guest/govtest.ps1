# govtest.ps1 - exercise the dbgcap CPU governor (NEXT.md 0bn): idle, single-CPU loads, an all-CPU load, ramp-down, and an A/B benchmark of the governor against the static cap.
#   Run as SYSTEM on the phone:  powershell -NoProfile -ExecutionPolicy Bypass -File C:\rm9\link\govtest.ps1 [-Quick]     Log: C:\rm9\govtest.txt (also written to stdout)
param([switch]$Quick)
. C:\rm9\link\dbgcap.ps1
Add-Type -TypeDefinition @'
using System;
using System.Threading;
using System.Runtime.InteropServices;
public static class Spin {
  [DllImport("kernel32.dll")] static extern IntPtr GetCurrentThread();
  [DllImport("kernel32.dll")] static extern UIntPtr SetThreadAffinityMask(IntPtr h, UIntPtr m);
  public static volatile bool Stop;
  public static long[] Count = new long[16];
  public static void Start(int cpu) {
    Thread t = new Thread(() => {
      SetThreadAffinityMask(GetCurrentThread(), (UIntPtr)(1UL << cpu));
      long n = 0;
      while (!Stop) { for (int i = 0; i < 1000; i++) n += i ^ (n >> 3); Count[cpu]++; }
    });
    t.IsBackground = true; t.Start();
  }
}
'@
$log = 'C:\rm9\govtest.txt'
function W($m) { [Console]::WriteLine($m); ("{0:HH:mm:ss} {1}" -f (Get-Date), $m) | Out-File -Append -Encoding ascii $log }
function BatC([uint32]$v) { $s = [BitConverter]::ToInt32([BitConverter]::GetBytes($v), 0); if ($s -eq -32768) { 'n/a' } else { '{0:F2}C' -f ($s / 100.0) } }
function Snap([string]$ph, [double]$t) {
    $g = DbgGov 0 0
    if (-not $g) { W "$ph : DbgGov failed"; return $null }
    W ("{0,5:F1}s {1,-8} on={2} B={3} T={4,5:F1}C idx={5},{6},{7},{8} MHz={9},{10},{11},{12} ceil={13},{14},{15},{16} util={17},{18},{19},{20} busy={21} bat={22} bcap={23}" -f $t, $ph, $g[0], $g[1], ([int]$g[2] / 10.0), $g[4], $g[5], $g[6], $g[7], $g[8], $g[9], $g[10], $g[11], $g[12], $g[13], $g[14], $g[15], $g[16], $g[17], $g[18], $g[19], (($g[20..27]) -join '/'), (BatC $g[48]), $g[49])
    return ,$g
}
function Phase([string]$ph, [double]$sec, [int[]]$cpus) {
    [Spin]::Stop = $false
    foreach ($c in $cpus) { [Spin]::Start($c) }
    $t0 = Get-Date; $hot = $false
    while (((Get-Date) - $t0).TotalSeconds -lt $sec) {
        $g = Snap $ph ((Get-Date) - $t0).TotalSeconds
        if ($g -and [int]$g[2] -ge 900) { W "$ph : 90 C reached, ending the phase early"; break }
        Start-Sleep -Milliseconds 500
    }
    [Spin]::Stop = $true
    Start-Sleep -Milliseconds 400
}
function Bench([string]$label, [int]$cpu, [int]$ms) {
    [Spin]::Stop = $false
    $c0 = [Spin]::Count[$cpu]
    [Spin]::Start($cpu)
    Start-Sleep -Milliseconds $ms
    [Spin]::Stop = $true
    $c1 = [Spin]::Count[$cpu]
    Start-Sleep -Milliseconds 300
    $r = [Math]::Round(($c1 - $c0) / ($ms / 1000.0))
    W ("bench {0}: cpu{1} {2} k-iterations/s" -f $label, $cpu, $r)
    return $r
}
W '==== govtest start'
$g = DbgGov 0 0
if (-not $g) { W 'dbgcap IOCTL failed'; return }
W ("gov: on={0} wanted={1} ticks={2} levels(n)={3},{4},{5},{6} cpus={7} EPSS={8} guard={9} period={10} ms" -f $g[0], $g[47], $g[3], $g[36], $g[37], $g[38], $g[39], $g[42], $g[45], $g[46], $g[44])
if ($g[0] -eq 0) { W 'governor is off: switching it on'; $g = DbgGov 1 1; Start-Sleep 2 }
$idle = 8; $one = 8; $all = 15; $down = 12
if ($Quick) { $idle = 4; $one = 4; $all = 6; $down = 6 }
Phase 'idle' $idle @()
Phase 'cpu7' $one @(7)
Phase 'cpu2' $one @(2)
Phase 'cpu0' $one @(0)
Phase 'all8' $all @(0, 1, 2, 3, 4, 5, 6, 7)
Phase 'cooldown' $down @()
# A/B: static cap vs governor, same 3 s burst on the prime core (7) and a mid core (2)
[void](DbgGov 1 0); Start-Sleep 3
[void](Snap 'static' 0)
$s7 = Bench 'static' 7 3000; $s2 = Bench 'static' 2 3000
[void](DbgGov 1 1); Start-Sleep 2
$g7 = Bench 'gov' 7 3000; $g2 = Bench 'gov' 2 3000
W ("speed-up of the governor over the static cap: cpu7 {0:F2}x  cpu2 {1:F2}x" -f ($g7 / [Math]::Max(1.0, [double]$s7)), ($g2 / [Math]::Max(1.0, [double]$s2)))
$g = Snap 'end' 0
W ("ups={0} errors={1} last status={2:X8}" -f $g[43], $g[41], $g[40])
W '==== govtest done'
