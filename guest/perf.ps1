# S:\rm9\perf.ps1 - baseline: CPU/memory/storage speed and system facts (run as SYSTEM from run.cmd).  Output -> C:\rm9\perf.txt
$out = 'C:\rm9\perf.txt'
function P($m) { Add-Content -Path $out -Value $m }
Set-Content -Path $out -Value ("perf start " + (Get-Date))
try {
    $cs = Get-CimInstance Win32_ComputerSystem
    P ("Computer: {0} {1}  RAM={2:N2} GB  Cores={3} Logical={4}" -f $cs.Manufacturer, $cs.Model, ($cs.TotalPhysicalMemory / 1GB), $cs.NumberOfProcessors, $cs.NumberOfLogicalProcessors)
    foreach ($c in (Get-CimInstance Win32_Processor)) { P ("CPU: {0} cores={1} logical={2} max={3} MHz cur={4} MHz" -f $c.Name, $c.NumberOfCores, $c.NumberOfLogicalProcessors, $c.MaxClockSpeed, $c.CurrentClockSpeed) }
    $b = Get-CimInstance Win32_BIOS
    P ("BIOS: {0} {1} {2}" -f $b.Manufacturer, $b.SMBIOSBIOSVersion, $b.ReleaseDate)
    $os = Get-CimInstance Win32_OperatingSystem
    P ("OS: {0} build {1}  boot={2}  freeMem={3:N2} GB" -f $os.Caption, $os.BuildNumber, $os.LastBootUpTime, ($os.FreePhysicalMemory / 1MB))
    P ("Battery objects: " + @(Get-CimInstance Win32_Battery -ErrorAction SilentlyContinue).Count)
    P ("Thermal zones: " + @(Get-CimInstance -Namespace root/wmi -ClassName MSAcpi_ThermalZoneTemperature -ErrorAction SilentlyContinue).Count)
} catch { P ("facts error: " + $_) }

try {
    Add-Type -TypeDefinition @'
using System;
using System.Diagnostics;
using System.Threading.Tasks;
public static class Bench {
    public static double IntLoop(long n) { var sw = Stopwatch.StartNew(); long a = 1, b = 2; for (long i = 0; i < n; i++) { a = a * 3 + b; b ^= a >> 7; } sw.Stop(); if (a == 42) Console.Write(""); return n / sw.Elapsed.TotalSeconds / 1e6; }
    public static double ParallelRun(long n, int threads) { var sw = Stopwatch.StartNew(); System.Threading.Tasks.Parallel.For(0, threads, new ParallelOptions { MaxDegreeOfParallelism = threads }, t => { IntLoop(n); }); sw.Stop(); return (double)n * threads / sw.Elapsed.TotalSeconds / 1e6; }
    public static double MemCopyGBs(int mb) { var a = new byte[mb * 1024 * 1024]; var b = new byte[mb * 1024 * 1024]; var sw = Stopwatch.StartNew(); for (int k = 0; k < 4; k++) Buffer.BlockCopy(a, 0, b, 0, a.Length); sw.Stop(); return 4.0 * mb / 1024.0 / sw.Elapsed.TotalSeconds; }
}
'@
    P ("1-thread integer loop : {0:N0} Mops/s" -f [Bench]::IntLoop(300000000))
    P ("1-thread again        : {0:N0} Mops/s" -f [Bench]::IntLoop(300000000))
    foreach ($t in 2, 4, 8) { P ("{0}-thread aggregate    : {1:N0} Mops/s" -f $t, [Bench]::ParallelRun(150000000, $t)) }
    P ("memory copy           : {0:N2} GB/s" -f [Bench]::MemCopyGBs(256))
} catch { P ("bench error: " + $_) }

try {
    $f = 'C:\rm9\iotest.bin'
    $buf = New-Object byte[] (64MB)
    (New-Object Random 1).NextBytes($buf)
    $sw = [Diagnostics.Stopwatch]::StartNew()
    $fs = [IO.File]::Create($f)
    for ($i = 0; $i -lt 16; $i++) { $fs.Write($buf, 0, $buf.Length) }
    $fs.Flush($true); $fs.Close(); $sw.Stop()
    P ("storage write 1 GiB  : {0:N0} MB/s" -f (1024 / $sw.Elapsed.TotalSeconds))
    $sw.Restart()
    $fs = [IO.File]::OpenRead($f)
    while ($fs.Read($buf, 0, $buf.Length) -gt 0) {}
    $fs.Close(); $sw.Stop()
    P ("storage read 1 GiB   : {0:N0} MB/s (may be cached)" -f (1024 / $sw.Elapsed.TotalSeconds))
    Remove-Item $f -Force
} catch { P ("io error: " + $_) }
P ("perf end " + (Get-Date))
