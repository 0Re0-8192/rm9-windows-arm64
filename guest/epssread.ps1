# epssread.ps1 - READ-ONLY look at the CPU frequency hardware (EPSS cpufreq-hw, 4 frequency domains) while Windows idles, plus TSENS temperature, CPU load and the busiest processes.
# Compare with Android: freq-domain0 = cpu0-1, domain1 = cpu5-6, domain2 = cpu7, domain3 = cpu2-4 (this order was matched against /sys/devices/system/cpu on 2026-10-27).
# Registers (qcom-cpufreq-hw EPSS layout): +0x20 domain state, +0x100.. frequency LUT (low 8 bits = L value, x 19.2 MHz), +0x320 current performance-state index, +0x3C4 cycle counter.
# Log: S:\rm9\epss.txt (WriteThrough).  No register is written.  Runs after dbgcap's hang/overheat guard is on.
. S:\rm9\rm9io.ps1
. S:\rm9\dbgcap.ps1
$fs = New-Object IO.FileStream('S:\rm9\epss.txt', [IO.FileMode]::Append, [IO.FileAccess]::Write, [IO.FileShare]::ReadWrite, 4096, [IO.FileOptions]::WriteThrough)
function L($s) { $b = [Text.Encoding]::ASCII.GetBytes(((Get-Date -Format 'HH:mm:ss.fff') + ' ' + $s + "`r`n")); $fs.Write($b, 0, $b.Length); $fs.Flush() }
function Hottest {
    if (-not [DbgCap]::Open()) { return $null }
    $buf = New-Object byte[] 32; $ret = 0
    $code = [Convert]::ToUInt32('8F002820', 16)
    try { $ok = [DbgCap]::DeviceIoControl([DbgCap]::H, $code, $buf, 4, $buf, 32, [ref]$ret, [IntPtr]::Zero) } catch { return $null }
    if (-not $ok) { return $null }
    return [BitConverter]::ToInt32($buf, 4) / 10.0
}
L '=== epssread start'
if ((Get-Service rm9io -ErrorAction SilentlyContinue).Status -ne 'Running') { Start-Service rm9io -ErrorAction SilentlyContinue; Start-Sleep 1 }
$bases = @(0x17D91000, 0x17D92000, 0x17D93000, 0x17D94000)
$names = @('dom0(cpu0-1)', 'dom1(cpu5-6)', 'dom2(cpu7)', 'dom3(cpu2-4)')
$lut = @{}
for ($d = 0; $d -lt 4; $d++) {
    try {
        $w = Rm9Read ([uint64]($bases[$d] + 0x100)) 40
        $mhz = @(); foreach ($x in $w) { $lv = $x -band 0xFF; if ($lv -ne 0) { $mhz += [int]($lv * 19.2) } }
        $lut[$d] = $w
        L ($names[$d] + ' LUT MHz: ' + (($mhz | Select-Object -Unique) -join ' '))
    } catch { L ($names[$d] + ' LUT read failed: ' + $_.Exception.Message) }
}
$prev = @{}
for ($i = 0; $i -lt 40; $i++) {
    $t = Hottest
    $line = ('t={0}s hottest={1}C' -f ($i * 3), $t)
    for ($d = 0; $d -lt 4; $d++) {
        try {
            $st = Rm9Read ([uint64]($bases[$d] + 0x20)) 1
            $ps = Rm9Read ([uint64]($bases[$d] + 0x320)) 1
            $cy = Rm9Read ([uint64]($bases[$d] + 0x3C4)) 1
            $idx = [int]($ps[0] -band 0x3F)
            $mhz = if ($lut[$d] -and $idx -lt $lut[$d].Count) { [int](($lut[$d][$idx] -band 0xFF) * 19.2) } else { -1 }
            $dcy = ''
            if ($prev[$d] -ne $null) { $dcy = ' dCyc/s=' + [int](([uint32]($cy[0] - $prev[$d])) / 3) }
            $prev[$d] = $cy[0]
            $line += (' | {0} perf={1} {2}MHz state=0x{3:X8}{4}' -f $names[$d], $idx, $mhz, $st[0], $dcy)
        } catch { $line += (' | ' + $names[$d] + ' read failed') }
    }
    L $line
    if ($i % 5 -eq 0) {
        try { $c = (Get-Counter '\Processor(_Total)\% Processor Time' -ErrorAction Stop).CounterSamples[0].CookedValue; L ('  cpu load total=' + [int]$c + '%') } catch { L '  cpu load n/a' }
        try { $top = Get-Process | Sort-Object CPU -Descending | Select-Object -First 5 | ForEach-Object { '{0}:{1:N0}s' -f $_.ProcessName, $_.CPU }; L ('  top cpu time: ' + ($top -join ', ')) } catch {}
    }
    Start-Sleep -Seconds 3
}
L '=== epssread end'
$fs.Close()
