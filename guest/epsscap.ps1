# epsscap.ps1 - cap the CPU frequency through the EPSS performance-state register (+0x320 of each frequency domain, the same register Linux's qcom-cpufreq-hw writes) and watch what it does.
# Windows without FxPPM never lowers the frequency (everything sits at the boot-time maximum), so an idle-but-busy Windows runs at 85-94 C.  The write is lost on reboot.  Runs after dbgcap's guard is on.
# Targets (MHz, nearest LUT entry): dom0 cpu0-1 1344, dom1 cpu5-6 1498, dom2 cpu7 1478, dom3 cpu2-4 1498.
# Phases: baseline 30 s (no write), cap on (re-asserted every 3 s) 45 s idle, then 25 s of 4 busy loops, then 20 s idle.  Log S:\rm9\epsscap.txt (WriteThrough).
. S:\rm9\rm9io.ps1
. S:\rm9\dbgcap.ps1
$fs = New-Object IO.FileStream('S:\rm9\epsscap.txt', [IO.FileMode]::Append, [IO.FileAccess]::Write, [IO.FileShare]::ReadWrite, 4096, [IO.FileOptions]::WriteThrough)
function L($s) { $b = [Text.Encoding]::ASCII.GetBytes(((Get-Date -Format 'HH:mm:ss.fff') + ' ' + $s + "`r`n")); $fs.Write($b, 0, $b.Length); $fs.Flush() }
function Hottest {
    if (-not [DbgCap]::Open()) { return $null }
    $buf = New-Object byte[] 32; $ret = 0
    $code = [Convert]::ToUInt32('8F002820', 16)
    try { $ok = [DbgCap]::DeviceIoControl([DbgCap]::H, $code, $buf, 4, $buf, 32, [ref]$ret, [IntPtr]::Zero) } catch { return $null }
    if (-not $ok) { return $null }
    return [BitConverter]::ToInt32($buf, 4) / 10.0
}
function RdTry([uint64]$a, [uint32]$n = 1) {
    for ($k = 0; $k -lt 3; $k++) { try { return Rm9Read $a $n } catch { $script:lastErr = $_.Exception.Message; Start-Sleep -Milliseconds 20 } }
    return $null
}
L '=== epsscap start'
if ((Get-Service rm9io -ErrorAction SilentlyContinue).Status -ne 'Running') { Start-Service rm9io -ErrorAction SilentlyContinue; Start-Sleep 1 }
$bases = @(0x17D91000, 0x17D92000, 0x17D93000, 0x17D94000)
$names = @('dom0(cpu0-1)', 'dom1(cpu5-6)', 'dom2(cpu7)', 'dom3(cpu2-4)')
$targets = @(1344, 1498, 1478, 1498)
$lut = @{}; $capIdx = @{}
for ($d = 0; $d -lt 4; $d++) {
    $w = RdTry ([uint64]($bases[$d] + 0x100)) 40
    if (-not $w) { L ($names[$d] + ' LUT read failed: ' + $script:lastErr); L 'abort: cannot read the frequency table'; $fs.Close(); exit 2 }
    $lut[$d] = $w
    $best = 0; $bd = 99999
    for ($i = 0; $i -lt 40; $i++) { $lv = $w[$i] -band 0xFF; if ($lv -eq 0) { break }; $m = [int]($lv * 19.2); $dd = [Math]::Abs($m - $targets[$d]); if ($dd -lt $bd) { $bd = $dd; $best = $i } }
    $capIdx[$d] = $best
    L ($names[$d] + ' target ' + $targets[$d] + ' MHz -> LUT index ' + $best + ' = ' + [int](($w[$best] -band 0xFF) * 19.2) + ' MHz')
}
$prev = @{}; $fail = 0
function Sample([string]$tag) {
    $t = Hottest
    $line = ('{0} hottest={1}C' -f $tag, $t)
    for ($d = 0; $d -lt 4; $d++) {
        $ps = RdTry ([uint64]($bases[$d] + 0x320)) 1
        $cy = RdTry ([uint64]($bases[$d] + 0x3C4)) 1
        if (-not $ps -or -not $cy) { $line += (' | ' + $names[$d] + ' read failed: ' + $script:lastErr); $script:fail++; continue }
        $idx = [int]($ps[0] -band 0x3F)
        $mhz = [int](($lut[$d][$idx] -band 0xFF) * 19.2)
        $dcy = ''
        if ($prev[$d] -ne $null) { $dcy = ' dCyc/s=' + [int](([uint32]($cy[0] - $prev[$d])) / 3) }
        $prev[$d] = $cy[0]
        $line += (' | {0} {1}MHz{2}' -f $names[$d], $mhz, $dcy)
    }
    L $line
    return $t
}
function ApplyCap([int]$low) {
    for ($d = 0; $d -lt 4; $d++) { $v = if ($low) { 0 } else { $capIdx[$d] }; try { Rm9Write ([uint64]($bases[$d] + 0x320)) ([uint32]$v) 0 } catch { L ('write failed ' + $names[$d] + ': ' + $_.Exception.Message) } }
}
L '--- phase 1: baseline (no write)'
for ($i = 0; $i -lt 10; $i++) { $null = Sample ('base t=' + ($i * 3)); Start-Sleep 3 }
L '--- phase 2: cap on'
$hot = 0
for ($i = 0; $i -lt 15; $i++) { ApplyCap 0; $t = Sample ('cap  t=' + ($i * 3)); if ($t -ne $null -and $t -ge 95) { $hot++; ApplyCap 1; L 'HOT: dropped to the lowest state' }; Start-Sleep 3 }
L '--- phase 3: cap on + 4 busy loops (25 s)'
$jobs = 1..4 | ForEach-Object { Start-Job -ScriptBlock { $e = (Get-Date).AddSeconds(25); while ((Get-Date) -lt $e) { $x = 0; for ($k = 0; $k -lt 20000; $k++) { $x += $k } } } }
for ($i = 0; $i -lt 9; $i++) { ApplyCap 0; $t = Sample ('load t=' + ($i * 3)); if ($t -ne $null -and $t -ge 95) { ApplyCap 1; L 'HOT: dropped to the lowest state'; break }; Start-Sleep 3 }
$jobs | Stop-Job -ErrorAction SilentlyContinue; $jobs | Remove-Job -Force -ErrorAction SilentlyContinue
L '--- phase 4: cap on, idle again'
for ($i = 0; $i -lt 7; $i++) { ApplyCap 0; $null = Sample ('idle t=' + ($i * 3)); Start-Sleep 3 }
L ('=== epsscap end, read failures=' + $fail)
$fs.Close()
