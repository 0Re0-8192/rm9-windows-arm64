# rpfix.ps1 - Root Port + Wi-Fi bring-up in the right order.  At boot the root port's MSI capability is hidden by MuChain (a visible MSI makes Windows' HAL send MAPD Size 9 to the ITS before any user-mode code runs -> ITS stalls -> CLOCK_WATCHDOG).
# pci.sys' bus FDO for the root port fails with 0xC0000034 when there is no interrupt resource (IoConnectInterruptEx for the express port), so: (1) start the ITS stall fixer, (2) give the root port its MSI capability back (DBI PM cap next pointer 0x70 -> 0x50),
# (3) restart the root port (its MAPD Size 9 is rewritten to 7 by the fixer), (4) when the endpoint shows up enable qcwlan and restart it.  Log: S:\rm9\wifi_rpfix.txt (FAT)
$o = 'S:\rm9\wifi_rpfix.txt'
$fs = New-Object IO.FileStream($o, [IO.FileMode]::Append, [IO.FileAccess]::Write, [IO.FileShare]::ReadWrite, 4096, [IO.FileOptions]::WriteThrough)
function L($m) { $b = [Text.Encoding]::ASCII.GetBytes("$(Get-Date -Format 'HH:mm:ss.fff') $m`r`n"); $fs.Write($b, 0, $b.Length); $fs.Flush($true) }
# S:\rm9\prod.flag (2026-10-31, esp_run_prod_wifi.cmd): production mode = bring the Wi-Fi up exactly like the test runs, then STAY: no ETW trace into the ESP, a shorter connect watch, no cleanup, no restart.
$script:prod = Test-Path S:\rm9\prod.flag
function A([string]$h) { [Convert]::ToUInt64($h, 16) }
function U([string]$h) { [Convert]::ToUInt32($h, 16) }
function Hx($a) { ($a | ForEach-Object { '{0:X8}' -f $_ }) -join ' ' }
. C:\rm9\link\rm9io.ps1
if (Test-Path C:\rm9\link\dbgcap.ps1) { . C:\rm9\link\dbgcap.ps1; $script:dbgOn = $true } else { $script:dbgOn = $false }
$script:dfs = New-Object IO.FileStream('S:\rm9\dbgcap.txt', [IO.FileMode]::Append, [IO.FileAccess]::Write, [IO.FileShare]::ReadWrite, 4096, [IO.FileOptions]::WriteThrough)
function DbgFlush() {
    if (-not $script:dbgOn) { return }
    try {
        for ($n = 0; $n -lt 8; $n++) {
            $t = DbgRead
            if (-not $t) { break }
            $b = [Text.Encoding]::ASCII.GetBytes($t); $script:dfs.Write($b, 0, $b.Length); $script:dfs.Flush($true)
        }
    } catch { }
}

if ((Get-Service rm9io -ErrorAction SilentlyContinue).Status -ne 'Running') { Start-Service rm9io -ErrorAction SilentlyContinue; Start-Sleep 1 }
Start-Sleep 70
L 'rpfix start'
$its = A '17140000'
function Its32($off) { (Rm9Read ($its + $off) 1)[0] }
$cb = Its32 0x80
$q = [uint64]($cb -band (U 'FFFFF000'))
if ($q -eq 0) { L 'no ITS queue (HAL has not set the ITS up): stopping'; return }
$l1 = [uint64]((Its32 0x100) -band (U 'FFFFF000'))
L ('CBASER ' + ('{0:X8}' -f (Its32 0x84)) + ':' + ('{0:X8}' -f $cb) + ' BASER0 ' + ('{0:X8}' -f (Its32 0x104)) + ':' + ('{0:X8}' -f (Its32 0x100)) + ' L1 @' + ('{0:X}' -f $l1) + ' queue @' + ('{0:X}' -f $q) + ' CREADR ' + ('{0:X8}' -f (Its32 0x90)) + ' CWRITER ' + ('{0:X8}' -f (Its32 0x88)))
L ('crumb header @D7E00000 (sig,start,size,data): ' + (Hx (Rm9Read (A 'D7E00000') 8)))
CrumbDump 'start'
# read-only: the commands Windows itself put into the ITS queue (MAPD/MAPC/MAPTI/...), to see the RDbase / ICID it used
for ($s = 0; $s -lt 40; $s++) { $w = Rm9Read ($q + 32 * $s) 8; if (($w | Measure-Object -Sum).Sum -ne 0) { L ('  WinCmd slot ' + ('{0:X3}' -f (32 * $s)) + ': ' + (Hx $w)) } }
$pool = @((A 'D7FF4000'), (A 'D7FF5000'), (A 'D7FF6000'), (A 'D7FF7000')); $script:poolUsed = 0
$V = U '80000000'
$handled = @{}
function State() { 'cr=' + ('{0:X8}' -f (Its32 0x90)) + ' cw=' + ('{0:X8}' -f (Its32 0x88)) }
function Fix([uint32]$cr) {
    $off = [uint64]($cr -band (U 'FFFFFFFE'))
    $w = Rm9Read ($q + $off) 8
    L ('STALL at queue+' + ('{0:X}' -f $off) + ': ' + (Hx $w))
    if (($w[0] -band 0xFF) -ne 8) { L 'not a MAPD: not touching'; return $false }
    $devid = $w[1]; $size = $w[2] -band 0x1F
    if ($size -gt 7) { Rm9Write ($q + $off + 8) (($w[2] -band (U 'FFFFFFE0')) -bor 7); L "  MAPD size $size -> 7" }
    $idx = [uint64]($devid -shr 9)
    $e = Rm9Read ($l1 + 8 * $idx) 2
    L ("  L1[$idx] = " + (Hx $e))
    if (($e[0] -eq 0) -and ($e[1] -eq 0)) {
        if ($script:poolUsed -ge $pool.Count) { L '  no free level-2 page'; return $false }
        $pg = $pool[$script:poolUsed]; $script:poolUsed++
        for ($i = 0; $i -lt 1024; $i++) { Rm9Write ($pg + 4 * $i) 0 }
        Rm9Write ($l1 + 8 * $idx) ([uint32]$pg); Rm9Write ($l1 + 8 * $idx + 4) $V
        L ('  installed level-2 page @' + ('{0:X}' -f $pg) + ' -> L1[' + $idx + '] = ' + (Hx (Rm9Read ($l1 + 8 * $idx) 2)))
    }
    $cw = Its32 0x88
    Rm9Write ($its + 0x88) ($cw -bor 1)       # GITS_CWRITER.Retry
    Start-Sleep -Milliseconds 30
    L ('  after Retry: ' + (State))
    return $true
}
function Burst() {
    # Windows' Interrupts/sec counter of CPU 0 is sampled by typeperf (S:\rm9\perf.csv); a burst of INT commands in the middle must show up there if LPI 0x2010 reaches the CPU
    $pf = 'S:\rm9\perf.csv'
    Remove-Item $pf -ErrorAction SilentlyContinue
    Start-Process typeperf -ArgumentList '"\Processor Information(0,0)\Interrupts/sec" "\Processor Information(0,0)\DPCs Queued/sec" -si 1 -sc 14 -y -o S:\rm9\perf.csv' -WindowStyle Hidden
    Start-Sleep -Seconds 4
    L '  Burst: start'
    $n = 0; $t0 = Get-Date
    [uint32[]]$x = @(3, 0x1401, 0, 0, 0, 0, 0, 0)
    while (((Get-Date) - $t0).TotalSeconds -lt 4) {
        $cw0 = Its32 0x88; $cr0 = Its32 0x90
        if (($cr0 -band 1) -or ((($cw0 - $cr0) -band 0xFFF) -gt 0x800)) { Start-Sleep -Milliseconds 5; continue }
        $slot = [uint64]($cw0 -band (U 'FFFFFFFE'))
        for ($i = 0; $i -lt 8; $i++) { Rm9Write ($q + $slot + 4 * $i) $x[$i] }
        Rm9Write ($its + 0x88) ([uint32](($slot + 0x20) -band 0xFFF))
        $n++
        if (($n % 25) -eq 0) { IsrWatch }
    }
    IsrWatch
    L ('  Burst: ' + $n + ' INT commands in 4 s, ' + (State))
    Start-Sleep -Seconds 7
    L ('  Burst: perf.csv ' + $(if (Test-Path $pf) { (Get-Item $pf).Length } else { 'missing' }) + ' bytes')
}
function LpiDirect() {
    # GICR_SETLPIR (RD frame +0x40): make LPI 0x2010.. pending without the ITS.  If the driver's ISR counters move, the CPU / redistributor / HAL side is fine and the ITS path is what fails.
    $gr = A '17180000'
    $ty = Rm9Read ($gr + 8) 2
    L ('  LpiDirect: GICR0 TYPER=' + ('{0:X8}' -f $ty[1]) + ':' + ('{0:X8}' -f $ty[0]) + ' CTLR=' + ('{0:X8}' -f (Rm9Read $gr 1)[0]) + ' WAKER=' + ('{0:X8}' -f (Rm9Read ($gr + 0x14) 1)[0]))
    foreach ($id in @(0x2010, 0x2011, 0x2010)) {
        Rm9Write ($gr + 0x44) 0
        Rm9Write ($gr + 0x40) ([uint32]$id)
        Start-Sleep -Milliseconds 300
        L ('  LpiDirect: SETLPIR ' + ('{0:X}' -f $id) + ' written')
        IsrWatch
    }
}
function Phase([string]$name, [uint32[]]$cmd, [int]$sec) {
    # send the same command as fast as the ITS takes it for $sec seconds, busy-waiting (no timers) when the queue is full
    $n = 0; $t0 = Get-Date
    while (((Get-Date) - $t0).TotalSeconds -lt $sec) {
        $cw0 = Its32 0x88; $cr0 = Its32 0x90
        if (($cr0 -band 1) -or ((($cw0 - $cr0) -band 0xFFF) -gt 0x800)) { continue }
        $slot = [uint64]($cw0 -band (U 'FFFFFFFE'))
        for ($i = 0; $i -lt 8; $i++) { Rm9Write ($q + $slot + 4 * $i) $cmd[$i] }
        Rm9Write ($its + 0x88) ([uint32](($slot + 0x20) -band 0xFFF))
        $n++
    }
    L ('  Phase ' + $name + ': ' + $n + ' commands in ' + $sec + ' s ' + (State))
    LpiState ('after ' + $name)
    IsrWatch
}
function ItsDiff() {
    # control experiment: Interrupts/sec of CPU 0 (typeperf, 1 Hz) while the ITS gets SYNC commands (no interrupt) and then INT commands (LPI) of the same rate
    $pf = 'S:\rm9\perf.csv'
    Remove-Item $pf -ErrorAction SilentlyContinue
    Start-Process typeperf -ArgumentList '"\Processor Information(0,0)\Interrupts/sec" "\Processor Information(0,0)\DPCs Queued/sec" -si 1 -sc 40 -y -o S:\rm9\perf.csv' -WindowStyle Hidden
    Start-Sleep -Seconds 3
    $now = (Get-Date).ToString('HH:mm:ss.fff'); L ('  Diff: start ' + $now)
    Phase 'SYNC' ([uint32[]](5, 0, 0, 0, 0, 0, 0, 0)) 4
    Start-Sleep -Seconds 2
    Phase 'INT-1401' ([uint32[]](3, 0x1401, 0, 0, 0, 0, 0, 0)) 4
    Start-Sleep -Seconds 2
    Phase 'SYNC' ([uint32[]](5, 0, 0, 0, 0, 0, 0, 0)) 4
    Start-Sleep -Seconds 2
    Phase 'INT-1301' ([uint32[]](3, 0x1301, 0, 0, 0, 0, 0, 0)) 4
    Start-Sleep -Seconds 2
    Phase 'SYNC' ([uint32[]](5, 0, 0, 0, 0, 0, 0, 0)) 4
    L '  Diff: end'
}
function LpiProbe() {
    # disable LPI 0x2010 (config byte), INT it, see whether the pending bit shows up, then enable it again and see whether it is taken
    $gr_ = A '17180000'
    $pb_ = [uint64]((Rm9Read ($gr_ + 0x70) 1)[0] -band (U 'FFFFF000')); $pq_ = [uint64]((Rm9Read ($gr_ + 0x78) 1)[0] -band (U 'FFFF0000'))
    $c0 = (Rm9Read ($pb_ + 0x10) 1)[0]
    Rm9Write ($pb_ + 0x10) ($c0 -band (U 'FFFFFFFE'))
    Rm9Write ($gr_ + 0xA0) 0x2010
    Start-Sleep -Milliseconds 20
    L ('  LpiProbe: cfg dword ' + ('{0:X8}' -f $c0) + ' -> ' + ('{0:X8}' -f (Rm9Read ($pb_ + 0x10) 1)[0]) + ' pending=' + (Hx (Rm9Read ($pq_ + 0x400) 2)))
    SendInt 'lpi-disabled'
    for ($t = 0; $t -lt 3; $t++) { Start-Sleep -Milliseconds 100; L ('  LpiProbe: after INT (disabled) +' + (100 * ($t + 1)) + 'ms pending=' + (Hx (Rm9Read ($pq_ + 0x400) 2))) }
    Rm9Write ($pb_ + 0x10) $c0
    Rm9Write ($gr_ + 0xA0) 0x2010
    for ($t = 0; $t -lt 4; $t++) { Start-Sleep -Milliseconds 100; L ('  LpiProbe: re-enabled +' + (100 * ($t + 1)) + 'ms pending=' + (Hx (Rm9Read ($pq_ + 0x400) 2)) + ' cfg=' + ('{0:X8}' -f (Rm9Read ($pb_ + 0x10) 1)[0])) }
}
function LpiState([string]$tag) {
    # full 64-bit PROPBASER / PENDBASER of redistributor 0 (the tables sit above 4 GB), LPI configuration bytes 0x2000..0x201F and the pending dwords for LPIs 0x2000..0x207F
    $gr = A '17180000'
    $pr = Rm9Read ($gr + 0x70) 2; $pe = Rm9Read ($gr + 0x78) 2
    $pbA = ([uint64]$pr[1] * 4294967296 + [uint64]($pr[0] -band (U 'FFFFF000')))
    $pqA = ([uint64]$pe[1] * 4294967296 + [uint64]($pe[0] -band (U 'FFFF0000')))
    $cfg = Hx (Rm9Read $pbA 8)
    $pend = Hx (Rm9Read ($pqA + 0x400) 4)
    L ('  LpiState ' + $tag + ': PROPBASER=' + ('{0:X8}' -f $pr[1]) + ':' + ('{0:X8}' -f $pr[0]) + ' PENDBASER=' + ('{0:X8}' -f $pe[1]) + ':' + ('{0:X8}' -f $pe[0]) + ' cfg[0x2000..0x201F]=' + $cfg + ' pend[0x2000..0x207F]=' + $pend)
}
function ItsDump([string]$tag) {
    L ('      ITT EP @AFFEB9000: ' + (Hx (Rm9Read (A 'AFFEB9000') 24)) + '   RP @AFFEBC000: ' + (Hx (Rm9Read (A 'AFFEBC000') 8)))
    # GITS_BASER0..7 (device / collection / ... tables) and what the ITS wrote into them for our MAPD / MAPC commands
    $o = 'ItsDump ' + $tag + ': CTLR=' + ('{0:X8}' -f (Its32 0)) + ' CBASER=' + ('{0:X8}' -f (Its32 0x84)) + ':' + ('{0:X8}' -f (Its32 0x80))
    L ('  ' + $o)
    for ($n = 0; $n -lt 8; $n++) {
        $lo = Its32 (0x100 + 8 * $n); $hi = Its32 (0x104 + 8 * $n)
        $type = ($hi -shr 24) -band 7; $esz = (($hi -shr 16) -band 0x1F) + 1; $ind = ($hi -shr 30) -band 1; $v = ($hi -shr 31) -band 1
        $pages = ($lo -band 0xFF) + 1; $pgsz = @(4096, 16384, 65536, 65536)[($lo -shr 8) -band 3]
        $pa = ([uint64]($hi -band 0xFFFF) * 4294967296) + [uint64]($lo -band (U 'FFFFF000'))
        L ('    BASER' + $n + ' = ' + ('{0:X8}' -f $hi) + ':' + ('{0:X8}' -f $lo) + ' type=' + $type + ' entrysz=' + $esz + ' indirect=' + $ind + ' valid=' + $v + ' pages=' + $pages + ' pagesz=' + $pgsz + ' pa=' + ('{0:X}' -f $pa))
        if ($v -eq 1 -and $pa -ne 0 -and ($type -eq 4 -or $type -eq 1) -and $pa -ge (A '80000000') -and $pa -lt (A 'B00000000')) {
            L ('      first 64 bytes: ' + (Hx (Rm9Read $pa 16)))
        }
    }
    # the level-2 device-table page for DeviceID 0x1401 (index 10) and 0x1301 (index 9) as Windows installed them
    foreach ($idx in 9, 10) {
        $e = Rm9Read ((A '8321C000') + 8 * $idx) 2
        $l2 = ([uint64]($e[1] -band 0xFFFF) * 4294967296) + [uint64]($e[0] -band (U 'FFFFF000'))
        if (($e[1] -band (U '80000000')) -ne 0 -and $l2 -ge (A '80000000') -and $l2 -lt (A 'B00000000')) {
            L ('      L1[' + $idx + '] = ' + (Hx $e) + ' -> L2 page ' + ('{0:X}' -f $l2) + ' dev 0x' + ('{0:X}' -f ($idx * 512 + 1)) + ' entry: ' + (Hx (Rm9Read ($l2 + 8) 4)) + ' entry0: ' + (Hx (Rm9Read $l2 4)))
        } else { L ('      L1[' + $idx + '] = ' + (Hx $e)) }
    }
}
function QCmd([uint32[]]$x) {
    $cw0 = Its32 0x88; $cr0 = Its32 0x90
    if ($cw0 -ne $cr0) { L ('  QCmd skipped: queue busy ' + (State)); return $false }
    $slot = [uint64]($cw0 -band (U 'FFFFFFFE'))
    for ($i = 0; $i -lt 8; $i++) { Rm9Write ($q + $slot + 4 * $i) $x[$i] }
    Rm9Write ($its + 0x88) ([uint32](($slot + 0x20) -band 0xFFF))
    for ($k = 0; $k -lt 40; $k++) { Start-Sleep -Milliseconds 5; if ((Its32 0x90) -eq (Its32 0x88)) { break } }
    return $true
}
function CollDump([string]$tag) {
    $lo = Its32 0x108; $hi = Its32 0x10C
    $pa = ([uint64]($hi -band 0xFFFF) * 4294967296) + [uint64]($lo -band (U 'FFFFF000'))
    L ('  CollDump ' + $tag + ' @' + ('{0:X}' -f $pa) + ': ' + (Hx (Rm9Read $pa 8)))
}
function MapcProbe() {
    # does the ITS record a collection in its table in memory (1-byte entries)?  Windows' own MAPC for ICID 0 leaves the table all zero.
    CollDump 'before'
    [void](QCmd ([uint32[]](9, 0, 7, 0, 0, 0x80000000, 0, 0)))      # MAPC ICID 7, RDbase 0, V=1
    [void](QCmd ([uint32[]](5, 0, 0, 0, 0, 0, 0, 0)))               # SYNC RDbase 0
    L ('  MapcProbe: MAPC icid 7 sent ' + (State))
    CollDump 'after MAPC icid 7'
    [void](QCmd ([uint32[]](9, 0, 0, 0, 0, 0x80000000, 0, 0)))      # MAPC ICID 0 again (same as Windows)
    [void](QCmd ([uint32[]](5, 0, 0, 0, 0, 0, 0, 0)))
    CollDump 'after MAPC icid 0'
    [void](QCmd ([uint32[]](9, 0, 3, 0, 0, 0x80000000, 0, 0)))      # MAPC ICID 3
    [void](QCmd ([uint32[]](5, 0, 0, 0, 0, 0, 0, 0)))
    CollDump 'after MAPC icid 3'
}
Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
public static class CpuNo { [DllImport("kernel32.dll")] public static extern uint GetCurrentProcessorNumber(); }
'@
function CpuInfo() {
    try {
        try {
            $ep = Get-PnpDevice | Where-Object { $_.InstanceId -like 'PCI*VEN_17CB&DEV_1107*' -and $_.Present } | Select-Object -First 1
            if ($ep) {
                $res = Get-CimInstance Win32_PnPAllocatedResource | Where-Object { $_.Dependent.DeviceID -eq $ep.InstanceId }
                foreach ($rr in $res) {
                    $a = $rr.Antecedent
                    $o = ($a | Select-Object -Property * | Out-String) -replace '\s+', ' '
                    L ('  EP resource: ' + $o.Substring(0, [Math]::Min(300, $o.Length)))
                }
                L ('  EP allocated resources: ' + @($res).Count)
            }
            $irqs = Get-CimInstance Win32_IRQResource | ForEach-Object { '' + $_.IRQNumber + '/' + $_.Name } | Where-Object { $_ -match '^(8[0-9]{3}|4294|-)' }
            L ('  IRQ resources >=8000 or negative: ' + (($irqs | Select-Object -First 60) -join ' ; '))
        } catch { L ('resource info failed: ' + $_) }
        try {
            $cs = Get-CimInstance Win32_ComputerSystem
            L ('HypervisorPresent=' + $cs.HypervisorPresent + ' Model=' + $cs.Model)
            $bo = (bcdedit /enum '{current}' 2>&1) -join ' | '
            L ('bcdedit current: ' + $bo.Substring(0, [Math]::Min(1500, $bo.Length)))
            $bo2 = (bcdedit /enum '{default}' 2>&1) -join ' | '
            if ($bo2 -ne $bo) { L ('bcdedit default: ' + $bo2.Substring(0, [Math]::Min(1500, $bo2.Length))) }
            $vs = (Get-CimInstance -ClassName Win32_DeviceGuard -Namespace root\Microsoft\Windows\DeviceGuard -ErrorAction SilentlyContinue)
            if ($vs) { L ('DeviceGuard: VBS=' + $vs.VirtualizationBasedSecurityStatus + ' services=' + ($vs.SecurityServicesRunning -join ',')) }
        } catch { L ('hv info failed: ' + $_) }
        $pr = Get-CimInstance Win32_Processor | ForEach-Object { $_.Name + ' cores=' + $_.NumberOfCores + ' logical=' + $_.NumberOfLogicalProcessors + ' id=' + $_.ProcessorId + ' status=' + $_.Status }
        L ('CPUs: ' + ($pr -join ' | ') + ' ProcessorCount=' + [Environment]::ProcessorCount)
        $seen = @{}
        for ($i = 0; $i -lt 400; $i++) { $seen[[string][CpuNo]::GetCurrentProcessorNumber()] = 1 + [int]$seen[[string][CpuNo]::GetCurrentProcessorNumber()]; if (($i % 20) -eq 0) { Start-Sleep -Milliseconds 5 } }
        L ('this script ran on logical CPUs: ' + (($seen.Keys | Sort-Object { [int]$_ } | ForEach-Object { $_ + 'x' + $seen[$_] }) -join ' '))
    } catch { L ('CpuInfo failed: ' + $_) }
}
function GicrProbe() {
    # redistributor n sits at 0x17180000 + n * 0x40000 (GICv4: four 64 KB frames each, see the MADT).  Log before every read so that a hang points at the culprit.
    foreach ($n in 0, 1, 2, 3, 4, 5, 6, 7) {
        $b = (A '17180000') + 0x40000 * $n
        L ('  GICR' + $n + ' @' + ('{0:X}' -f $b) + ': reading TYPER/WAKER')
        $t = Rm9Read ($b + 8) 2; $w = (Rm9Read ($b + 0x14) 1)[0]; $c = (Rm9Read $b 1)[0]
        L ('  GICR' + $n + ' TYPER=' + ('{0:X8}' -f $t[1]) + ':' + ('{0:X8}' -f $t[0]) + ' WAKER=' + ('{0:X8}' -f $w) + ' CTLR=' + ('{0:X8}' -f $c))
        $pr_ = Rm9Read ($b + 0x70) 2; $pe_ = Rm9Read ($b + 0x78) 2
        L ('  GICR' + $n + ' PROPBASER=' + ('{0:X8}' -f $pr_[1]) + ':' + ('{0:X8}' -f $pr_[0]) + ' PENDBASER=' + ('{0:X8}' -f $pe_[1]) + ':' + ('{0:X8}' -f $pe_[0]) + ' TYPER.DirectLPI=' + (($t[0] -shr 3) -band 1))
    }
}
function CpuSweep() {
    # re-target collection 0 (MAPC ICID 0) to different redistributors, then raise INT (dev 0x1401 event 0) and look at the driver's ISR counters.  Windows' own choice is RDbase 0 = CPU 0, which is mostly asleep.
    foreach ($r in 3, 4, 5, 6, 2, 7, 0) {
        [void](QCmd ([uint32[]](9, 0, 0, 0, ([uint32]($r * 65536)), 0x80000000, 0, 0)))     # MAPC ICID 0 -> RDbase r
        [void](QCmd ([uint32[]](5, 0, 0, 0, ([uint32]($r * 65536)), 0, 0, 0)))              # SYNC RDbase r
        [void](QCmd ([uint32[]](0x0D, 0, 0, 0, 0, 0, 0, 0)))                                 # INVALL ICID 0
        [void](QCmd ([uint32[]](5, 0, 0, 0, ([uint32]($r * 65536)), 0, 0, 0)))
        [void](QCmd ([uint32[]](3, 0x1401, 0, 0, 0, 0, 0, 0)))                               # INT dev 0x1401 event 0
        [void](QCmd ([uint32[]](5, 0, 0, 0, ([uint32]($r * 65536)), 0, 0, 0)))
        Start-Sleep -Milliseconds 400
        L ('  CpuSweep: collection 0 -> RDbase ' + $r + ' INT sent ' + (State))
        IsrWatch
    }
}
function IarSweep() {
    # collection 0 -> redistributor r, then dbgcap pins a thread to CPU r, masks interrupts (HIGH_LEVEL), raises INT dev 0x1401 event 0 and polls ICC_IAR1_EL1: an INTID back = the LPI reached this CPU
    foreach ($r in 3, 5, 7) {
        $res = DbgLpiTest $r 0 0 ([uint32]50000 -bor [uint32]2147483648 -bor [uint32]1073741824)
        if ($res) { L ('  IarSweep SGI control: CPU ' + $r + ' ran on ' + $res[0] + ' acknowledged ' + $res[1] + ' INTIDs: ' + (($res[2..9] | ForEach-Object { '{0:X}' -f $_ }) -join ',')) } else { L '  IarSweep SGI control failed' }
    }
    foreach ($r in 3, 5) {
        [void](QCmd ([uint32[]](9, 0, 0, 0, ([uint32]($r * 65536)), 0x80000000, 0, 0)))
        [void](QCmd ([uint32[]](5, 0, 0, 0, ([uint32]($r * 65536)), 0, 0, 0)))
        [void](QCmd ([uint32[]](0x0D, 0, 0, 0, 0, 0, 0, 0)))
        [void](QCmd ([uint32[]](5, 0, 0, 0, ([uint32]($r * 65536)), 0, 0, 0)))
        $res = DbgLpiTest $r 0x1401 0 ([uint32]50000 -bor [uint32]2147483648)
        if ($res) { L ('  IarSweep: target CPU ' + $r + ' -> ran on CPU ' + $res[0] + ' acknowledged ' + $res[1] + ' INTIDs: ' + (($res[2..9] | ForEach-Object { '{0:X}' -f $_ }) -join ',') + ' (before: ' + ('{0:X}' -f $res[10]) + ') kernel cw/cr before=' + ('{0:X}' -f $res[11]) + '/' + ('{0:X}' -f $res[12]) + ' after cr=' + ('{0:X}' -f $res[13]) + ' ICC PMR=' + ('{0:X}' -f $res[14]) + ' RPR=' + ('{0:X}' -f $res[15]) + ' IGRPEN1=' + ('{0:X}' -f $res[16]) + ' CTLR=' + ('{0:X}' -f $res[17]) + ' BPR1=' + ('{0:X}' -f $res[18]) + ' PMR(test)=' + ('{0:X}' -f $res[19]) + ' CurrentEL=' + ('{0:X}' -f $res[20]) + ' SRE=' + ('{0:X}' -f $res[21]) + ' ' + (State)) } else { L ('  IarSweep: target CPU ' + $r + ' DbgLpiTest failed') }
    }
}
function GicDump() {
    # distributor + ITS identification: GICD_CTLR (0), TYPER (4), IIDR (8), TYPER2 (0xC), PIDR2 (0xFFE8); ITS IIDR (4), TYPER lo (8), PIDR2 (0xFFE8); GICR0 IIDR (4), PIDR2, PWRR (0x24)
    $gd = A '17100000'
    L ('  GICD CTLR=' + ('{0:X8}' -f (Rm9Read $gd 1)[0]) + ' TYPER=' + ('{0:X8}' -f (Rm9Read ($gd + 4) 1)[0]) + ' IIDR=' + ('{0:X8}' -f (Rm9Read ($gd + 8) 1)[0]) + ' PIDR2=' + ('{0:X8}' -f (Rm9Read ($gd + 0xFFE8) 1)[0]))
    L ('  ITS CTLR=' + ('{0:X8}' -f (Its32 0)) + ' IIDR=' + ('{0:X8}' -f (Its32 4)) + ' TYPERlo=' + ('{0:X8}' -f (Its32 8)) + ' PIDR2=' + ('{0:X8}' -f (Its32 0xFFE8)))
    $gr = A '17180000'
    L ('  GICR0 IIDR=' + ('{0:X8}' -f (Rm9Read ($gr + 4) 1)[0]) + ' PIDR2=' + ('{0:X8}' -f (Rm9Read ($gr + 0xFFE8) 1)[0]) + ' CTLR=' + ('{0:X8}' -f (Rm9Read $gr 1)[0]))
    foreach ($n in 0, 3) {
        $b = $gr + 0x40000 * $n
        L ('  GICR' + $n + ' SGI frame: IGROUPR0=' + ('{0:X8}' -f (Rm9Read ($b + 0x10080) 1)[0]) + ' ISENABLER0=' + ('{0:X8}' -f (Rm9Read ($b + 0x10100) 1)[0]) + ' IPRIORITYR[28..31]=' + ('{0:X8}' -f (Rm9Read ($b + 0x1041C) 1)[0]))
    }
}
function StormTest() {
    # kernel-side INT storm for dev 0x1401 event 0 (LPI 0x2010); the driver's ISR counters should jump if the LPIs reach Windows' interrupt handler
    Remove-Item S:\rm9\perf.csv -ErrorAction SilentlyContinue
    Start-Process typeperf -ArgumentList '"\Processor Information(_Total)\Interrupts/sec" "\Processor Information(_Total)\DPCs Queued/sec" "\Processor Information(0,0)\Interrupts/sec" -si 1 -sc 30 -y -o S:\rm9\perf.csv' -WindowStyle Hidden
    Start-Sleep -Seconds 4
    L ('  Storm start ' + (Get-Date).ToString('HH:mm:ss.fff'))
    for ($n = 0; $n -lt 3; $n++) {
        $r = DbgItsStorm 0x1401 0 100000
        if ($r) { L ('  Storm ' + $n + ': sent ' + $r[0] + ' INTs in ' + $r[3] + ' ms, cw=' + ('{0:X}' -f $r[1]) + ' cr=' + ('{0:X}' -f $r[2])) } else { L '  Storm failed' }
        Start-Sleep -Milliseconds 3000
        IsrWatch
    }
    L ('  Storm end ' + (Get-Date).ToString('HH:mm:ss.fff'))
}
function Unstall() {
    # a failed command keeps the queue stalled (CREADR bit0); the only way out is CWRITER.Retry, which re-runs the same slot - so overwrite that slot with a harmless SYNC first
    $cr = Its32 0x90
    if (($cr -band 1) -ne 0) {
        $slot = [uint64]($cr -band (U 'FFFFFFFE'))
        L ('  ITS stalled at slot ' + ('{0:X}' -f $slot) + ': ' + (Hx (Rm9Read ($q + $slot) 8)) + ' -> replaced by SYNC, Retry')
        [uint32[]]$x = @(5, 0, 0, 0, 0, 0, 0, 0)
        for ($i = 0; $i -lt 8; $i++) { Rm9Write ($q + $slot + 4 * $i) $x[$i] }
        $cw = Its32 0x88
        Rm9Write ($its + 0x88) ($cw -bor 1)
        Start-Sleep -Milliseconds 30
        L ('  after Retry: ' + (State))
    }
}
function PollLpi([int]$cpu, [string]$tag) {
    $pr = Rm9Read ((A '17180000') + 0x70) 2
    $tab = ([uint64]$pr[1] * 4294967296) + [uint64]($pr[0] -band (U 'FFFFF000'))
    $d0 = (Rm9Read ($tab + 0x10) 1)[0]
    Rm9Write ($tab + 0x10) (($d0 -band (U 'FFFFFF00')) -bor 0x09)                         # LPI 0x2010 priority 0x08
    [void](QCmd ([uint32[]](0x0C, 0x1401, 0, 0, 0, 0, 0, 0)))                              # INV dev 0x1401 ev 0 (the hypervisor caches the LPI configuration)
    $res = DbgLpiTest $cpu 0x1401 0 ([uint32]5000 -bor [uint32]2147483648)
    if ($res) { L ('  PollLpi ' + $tag + ' cpu ' + $cpu + ' ran on ' + $res[0] + ' distinct INTIDs ' + $res[1] + ': ' + (($res[2..9] | ForEach-Object { '{0:X}' -f $_ }) -join ',') + '  (LPI = 2010)') } else { L ('  PollLpi ' + $tag + ' failed') }
    Rm9Write ($tab + 0x10) $d0
    [void](QCmd ([uint32[]](0x0C, 0x1401, 0, 0, 0, 0, 0, 0)))
}
function PrivateLpiTest([string]$tag) {
    L ('  PrivateLpiTest disabled: ITS mapping changes freeze Windows (see NEXT.md 0aa)'); return
    # event 15 (inside the device ITT size; event 100 was out of range and the MAPTI stalled) of the existing device 0x1401 -> LPI 0x2030 (priority 0x08); a brand-new DeviceID (0x1500 MAPD/MAPTI) froze the whole machine in the vITS, so do not use one
    $pr = Rm9Read ((A '17180000') + 0x70) 2
    $tab = ([uint64]$pr[1] * 4294967296) + [uint64]($pr[0] -band (U 'FFFFF000'))
    Rm9Write ($tab + 0x30) 0x09
    L ('  PrivateLpi ' + $tag + ': MAPTI dev 1401 ev 100 -> 2030')
    [void](QCmd ([uint32[]](9, 0, 0, 0, 0, 0x80000000, 0, 0)))                                     # MAPC icid 0 -> RDbase 0 (MAPTI stalls when the collection is not mapped; DISCARD froze the machine)
    L ('  PrivateLpi MAPC: ' + (State)); Unstall
    [void](QCmd ([uint32[]](0x0A, 0x1401, 100, 0x2030, 0, 0, 0, 0)))
    [void](QCmd ([uint32[]](0x0C, 0x1401, 100, 0, 0, 0, 0, 0)))
    [void](QCmd ([uint32[]](5, 0, 0, 0, 0, 0, 0, 0)))
    L ('  PrivateLpi MAPTI/INV/SYNC: ' + (State)); Unstall
    $res = DbgLpiTest 0 0x1401 100 ([uint32]5000 -bor [uint32]2147483648)
    if ($res) { L ('  PrivateLpi ' + $tag + ': ran on ' + $res[0] + ' distinct INTIDs ' + $res[1] + ': ' + (($res[2..9] | ForEach-Object { '{0:X}' -f $_ }) -join ',') + '   (the new LPI is 2030)') } else { L '  PrivateLpi: DbgLpiTest failed' }
    Rm9Write ($tab + 0x30) 0
}
function Unstall() {
    $cr = Its32 0x90
    if (($cr -band 1) -ne 0) {
        $slot = [uint64]($cr -band (U 'FFFFFFFE'))
        L ('  ITS stalled at slot ' + ('{0:X}' -f $slot) + ': ' + (Hx (Rm9Read ($q + $slot) 8)) + ' -> replaced by SYNC, Retry')
        [uint32[]]$x = @(5, 0, 0, 0, 0, 0, 0, 0)
        for ($i = 0; $i -lt 8; $i++) { Rm9Write ($q + $slot + 4 * $i) $x[$i] }
        $cw = Its32 0x88
        Rm9Write ($its + 0x88) ($cw -bor 1)
        Start-Sleep -Milliseconds 30
        L ('  after Retry: ' + (State))
    }
}
function HppirSweep() { for ($s = 0; $s -lt 40; $s++) { $w = Rm9Read ($q + 32 * $s) 8; if (($w | Measure-Object -Sum).Sum -ne 0) { L ('  WinCmd slot ' + ('{0:X3}' -f (32 * $s)) + ': ' + (Hx $w)) } } }
function RegDump([string]$tag) {
    # same offsets as ItsRegDump in MuChain.c; compare the two logs
    $gr = A '17180000'; $gd = A '17100000'
    foreach ($grp in @(@('GICR0 RD', $gr, @(0x00, 0x04, 0x08, 0x0C, 0x10, 0x14, 0x18, 0x1C, 0x20, 0x24, 0x28, 0x2C, 0x30, 0x34, 0x38, 0x3C, 0x40, 0x44, 0x48, 0x4C, 0x50, 0x54, 0x58, 0x5C, 0x60, 0x64, 0x68, 0x6C, 0x70, 0x74, 0x78, 0x7C, 0xC0, 0xFFD0, 0xFFD4, 0xFFD8, 0xFFDC, 0xFFE0, 0xFFE4, 0xFFE8, 0xFFEC, 0xFFF0, 0xFFF4, 0xFFF8, 0xFFFC)),
                       @('GICR0 SGI', ($gr + 0x10000), @(0x80, 0xD00, 0xD04, 0xD08, 0xD0C, 0xF00, 0xF04, 0xF08)),
                       @('GICD', $gd, @(0x00, 0x04, 0x08, 0x0C, 0x10, 0x14, 0x18, 0x1C, 0x20, 0x24, 0x28, 0x2C, 0x30, 0x34, 0x38, 0x3C, 0x40, 0x44, 0xFFD0, 0xFFD4, 0xFFD8, 0xFFDC, 0xFFE0, 0xFFE4, 0xFFE8, 0xFFEC, 0xFFF0, 0xFFF4, 0xFFF8, 0xFFFC)),
                       @('ITS', $its, @(0x00, 0x04, 0x08, 0x80, 0x84, 0x88, 0x8C, 0x90, 0x94, 0x100, 0x104, 0x108, 0x10C, 0x110, 0x114)))) {
        $o = ''
        foreach ($off in $grp[2]) {
            L ('  RegDump ' + $tag + ' ' + $grp[0] + ' reading 0x' + ('{0:X}' -f $off))
            $o += (' ' + ('{0:X}' -f $off) + '=' + ('{0:X}' -f (Rm9Read ($grp[1] + $off) 1)[0]))
        }
        L ('REGDUMP ' + $tag + ' ' + $grp[0] + ':' + $o)
    }
}
function MbiTest() {
    # S:\rm9\mbitest.flag: does the chip's own MSI write reach the GIC when it is sent to GICD_SETSPI_NSR (message-based SPI) instead of the ITS doorbell?  The endpoint's MSI address/data are rewritten for 6 s per variant,
    # the driver keeps polling (the chip keeps raising MHI events), and the (virtual) distributor's pending bits of SPI 768..783 (INTID 800..815 = GICD_ISPENDR[25] bits 0..15) are read before and after.  Nothing in the GIC is written.
    $gicd = A '17100000'; $msi = $ecamB + 0x50
    $origA = (Rm9Read ($msi + 4) 1)[0]; $origD = (Rm9Read ($msi + 8) 1)[0]
    L ('MbiTest: EP MSI cap ctrl=' + ('{0:X8}' -f (Rm9Read $msi 1)[0]) + ' addr=' + ('{0:X8}' -f $origA) + ' data=' + ('{0:X8}' -f $origD) + '; GICD_TYPER=' + ('{0:X8}' -f (Rm9Read ($gicd + 4) 1)[0]) + ' ISENABLER[25]=' + ('{0:X8}' -f (Rm9Read ($gicd + 0x100 + 4 * 25) 1)[0]) + ' ISPENDR[25]=' + ('{0:X8}' -f (Rm9Read ($gicd + 0x200 + 4 * 25) 1)[0]) + ' IROUTER[800]=' + (Hx (Rm9Read ($gicd + 0x6000 + 8 * 800) 2)))
    $origC = (Rm9Read $msi 1)[0]; $origM = (Rm9Read ($msi + 0xC) 1)[0]
    L ('MbiTest: ITT @FFEB9000: ' + (Hx (Rm9Read (A 'FFEB9000') 16)) + '  queue cr/cw: ' + (State)); LpiState 'mbitest'
    # Android runs the endpoint with MSI Multiple Message Enable = 5 (32 vectors), mask 0x04461000; Windows enables 16 (MME=4) with mask 0xFFFF0000.  Variant 1 gives the chip the Android shape (MME=5, no mask) with a DRAM sink.
    foreach ($v in @(@('DRAM sink, MME=5 mask=0 (Android shape)', (U 'D7FF9000'), (U '1220'), 5), @('DRAM sink (control: does the chip write at all while the ping runs?)', (U 'D7FF9000'), (U '1230'), 4), @('GICD_SETSPI_NSR data=INTID 800..815', (U '17100040'), 800, 4), @('MBI alias frame data=0..15', (U '17110040'), 0, 4))) {
        try {
            if ($v[1] -eq (U 'D7FF9000')) { Rm9Write (A 'D7FF9000') 0 }
            Rm9Write $msi ([uint32](($origC -band (U 'FF8FFFFF')) -bor ([uint32]$v[3] -shl 20)))
            if ($v[3] -eq 5) { Rm9Write ($msi + 0xC) 0 } else { Rm9Write ($msi + 0xC) $origM }
            $p0 = (Rm9Read ($gicd + 0x200 + 4 * 25) 1)[0]
            Rm9Write ($msi + 4) ([uint32]$v[1]); Rm9Write ($msi + 8) ([uint32]$v[2])
            L ('MbiTest [' + $v[0] + ']: MSI ctrl=' + ('{0:X8}' -f (Rm9Read $msi 1)[0]) + ' mask=' + ('{0:X8}' -f (Rm9Read ($msi + 0xC) 1)[0]) + ' addr=' + ('{0:X8}' -f (Rm9Read ($msi + 4) 1)[0]) + ' data=' + ('{0:X8}' -f (Rm9Read ($msi + 8) 1)[0]) + '  ISPENDR[25] before=' + ('{0:X8}' -f $p0))
            $null = Start-Process ping.exe -ArgumentList '-n 7 -l 1000 192.168.x.x' -WindowStyle Hidden      # traffic: the chip raises its RX / TX-completion / MHI interrupts while it carries frames
            for ($k = 0; $k -lt 6; $k++) { Start-Sleep 1; L ('  +' + ($k + 1) + 's ISPENDR[25]=' + ('{0:X8}' -f (Rm9Read ($gicd + 0x200 + 4 * 25) 1)[0]) + ' ISACTIVER[25]=' + ('{0:X8}' -f (Rm9Read ($gicd + 0x300 + 4 * 25) 1)[0]) + ' sink[D7FF9000]=' + ('{0:X8}' -f (Rm9Read (A 'D7FF9000') 1)[0])) }
        } catch { L ('MbiTest failed: ' + $_) }
        finally { Rm9Write ($msi + 4) $origA; Rm9Write ($msi + 8) $origD; Rm9Write $msi $origC; Rm9Write ($msi + 0xC) $origM }
    }
    L ('MbiTest: restored EP MSI addr=' + ('{0:X8}' -f (Rm9Read ($msi + 4) 1)[0]) + ' data=' + ('{0:X8}' -f (Rm9Read ($msi + 8) 1)[0]))
}
function IarCpu0() {
    # S:\rm9\iar0.flag (2026-10-30): the test that worked before boot (MuChain ItsTest: INT dev 0x1401 -> INTID acknowledged through ICC_IAR1_EL1 on CPU 0), done in Windows on the CPU the INT is really routed to.
    # IarSweep never did this: it first sent MAPC collection 0 -> CPU r, which Gunyah stalls on an already-mapped collection (the stall fixer turns it into SYNC), so the INT stayed routed to CPU 0 while the poll ran on CPU 3/5.
    # Pin to CPU 0, HIGH_LEVEL + DAIF.I masked, PMR opened, INT(0x1401, ev) + SYNC, poll IAR1 50 ms.  A ping runs in the background so the chip's own MSIs (LPI 0x2000+ev) can show up as well.
    try {
        if (-not $script:dbgOn) { L 'IarCpu0: no dbgcap'; return }
        $pg = Start-Process ping.exe -ArgumentList '-n', '40', '-w', '500', '192.168.x.x' -PassThru -WindowStyle Hidden
        Start-Sleep -Milliseconds 500
        foreach ($cpu in 0, 3) {
            $res = DbgLpiTest $cpu 0 0 ([uint32]50000 -bor [uint32]2147483648 -bor [uint32]1073741824)
            if ($res) { L ('IarCpu0 SGI control: CPU ' + $cpu + ' ran on ' + $res[0] + ' acknowledged ' + $res[1] + ' INTIDs: ' + (($res[2..9] | ForEach-Object { '{0:X}' -f $_ }) -join ',') + ' ICC PMR=' + ('{0:X}' -f $res[14]) + ' IGRPEN1=' + ('{0:X}' -f $res[16])) } else { L ('IarCpu0 SGI control: CPU ' + $cpu + ' DbgLpiTest failed') }
        }
        foreach ($ev in 0, 2, 4, 7, 9, 2) {
            $res = DbgLpiTest 0 0x1401 $ev ([uint32]50000 -bor [uint32]2147483648)
            if ($res) { L ('IarCpu0 INT ev ' + $ev + ': ran on CPU ' + $res[0] + ' acknowledged ' + $res[1] + ' INTIDs: ' + (($res[2..9] | ForEach-Object { '{0:X}' -f $_ }) -join ',') + ' (before: ' + ('{0:X}' -f $res[10]) + ') cw/cr before=' + ('{0:X}' -f $res[11]) + '/' + ('{0:X}' -f $res[12]) + ' after cr=' + ('{0:X}' -f $res[13]) + ' ' + (State)) } else { L ('IarCpu0 INT ev ' + $ev + ': DbgLpiTest failed') }
            Start-Sleep -Milliseconds 300
        }
        try { if ($pg -and -not $pg.HasExited) { $pg.Kill() } } catch { }
    } catch { L ('IarCpu0 failed: ' + $_) }
}
function SpinTest() {
    # S:\rm9\spin0.flag (2026-10-30): does a software INT (dev 0x1401) reach the driver's ISR while CPU 0 is kept RUNNING (never idle, so Gunyah never blocks the vCPU and the vPE stays resident), interrupts left enabled?
    # IarCpu0 (IRQs masked, IAR polled by hand on CPU 0) froze Windows right after its SGI controls passed, so this variant lets Windows take the interrupt itself and only reads the p7 ISR-entry counters (image+0x42B840) and the driver's counters.
    # Part 1 = control (CPU 0 idle, what every earlier test did), part 2 = a user-mode spinner pinned to CPU 0 at the highest thread priority.  Every step is logged BEFORE it runs so a freeze shows where.
    try {
        if (-not $script:dbgOn -or -not $script:qcBase) { L 'SpinTest: no dbgcap / driver base'; return }
        if (-not ('Spin0' -as [type])) {
            Add-Type -TypeDefinition @'
using System;
using System.Threading;
using System.Runtime.InteropServices;
public class Spin0 {
    [DllImport("kernel32.dll")] static extern IntPtr GetCurrentThread();
    [DllImport("kernel32.dll")] static extern UIntPtr SetThreadAffinityMask(IntPtr h, UIntPtr m);
    [DllImport("kernel32.dll")] static extern bool SetThreadPriority(IntPtr h, int p);
    public static volatile bool Stop;
    public static long Count;
    public static Thread Start(int cpu) {
        Stop = false; Count = 0;
        Thread t = new Thread(delegate() {
            SetThreadAffinityMask(GetCurrentThread(), (UIntPtr)(1UL << cpu));
            SetThreadPriority(GetCurrentThread(), 2);
            while (!Stop) { Count++; }
        });
        t.IsBackground = true; t.Start(); return t;
    }
}
'@
        }
        function CpuIntRaw([string]$cpu) { try { (Get-CimInstance Win32_PerfRawData_Counters_ProcessorInformation -Filter ("Name='" + $cpu + "'")).InterruptsPersec } catch { -1 } }
        $pp = DbgPoll $script:qcBase 0; L ('SpinTest: polling stopped ' + (Hx $pp))
        Start-Sleep 2
        foreach ($phase in 'control (CPU 0 idle)', 'spinner on CPU 0') {
            $th = $null
            if ($phase -like 'spinner*') {
                L 'SpinTest: starting the CPU 0 spinner'
                $th = [Spin0]::Start(0)
                Start-Sleep -Milliseconds 1500
                L ('SpinTest: spinner count after 1.5 s = ' + [Spin0]::Count)
            }
            $ci0 = CpuIntRaw '0,0'
            foreach ($ev in 0, 2, 4, 7, 9, 2) {
                L ('SpinTest [' + $phase + '] about to send INT ev ' + $ev)
                $h0 = KReadVa ($script:qcBase + 0x42B840) 64
                $c0 = KReadVa ($script:qcBase + 0x390A00 + 4 * $ev) 4
                $ok = QCmd ([uint32[]]@(3, 0x1401, $ev, 0, 0, 0, 0, 0))
                Start-Sleep -Milliseconds 400
                $c1 = KReadVa ($script:qcBase + 0x390A00 + 4 * $ev) 4
                $h1 = KReadVa ($script:qcBase + 0x42B840) 64
                L ('SpinTest [' + $phase + '] INT ev ' + $ev + ': sent=' + $ok + ' counter ' + (HexB $c0) + ' -> ' + (HexB $c1) + '  ISRhits ' + (HexB $h0) + ' -> ' + (HexB $h1) + '  spin=' + [Spin0]::Count + '  ' + (State))
            }
            $ci1 = CpuIntRaw '0,0'
            L ('SpinTest [' + $phase + '] CPU 0 raw interrupt counter ' + $ci0 + ' -> ' + $ci1)
            if ($th) { [Spin0]::Stop = $true; [void]$th.Join(3000); L 'SpinTest: spinner stopped' }
            Start-Sleep -Milliseconds 500
        }
        LpiState 'spintest'
        $pp = DbgPoll $script:qcBase $script:pollMs; L ('SpinTest: polling restarted ' + (Hx $pp))
    } catch { L ('SpinTest failed: ' + $_); try { [Spin0]::Stop = $true } catch { } }
}
function IrqDrvTest() {
    # S:\rm9\irqdrv.flag + S:\rm9\irqpkg\{rm9irq.sys,rm9irq.inf,rm9irq.cat} + S:\rm9\irqinstall.ps1 (+ p8): stage 1b of interrupt-driven Wi-Fi.  IoConnectInterruptEx refuses SPIs that the caller's PDO does not own (dbgcap: STATUS_NOT_SUPPORTED),
    # so a root-enumerated KMDF device (ROOT\RM9IRQ, drv\rm9irq) claims SPI 800..811 through its INF LogConfig and connects them itself; its "RM9IRQ ..." DbgPrint lines (resources, connect status, per-vector counts) land in S:\rm9\dbgcap.txt.
    # DeviceInstallDisabled is the Windows Update guard (NEXT.md 0): it is set to 0 only for the install and put back afterwards.
    try {
        $k = 'HKLM:\SYSTEM\CurrentControlSet\Services\DeviceInstall\Parameters'
        $orig = (Get-ItemProperty $k -Name DeviceInstallDisabled -ErrorAction SilentlyContinue).DeviceInstallDisabled
        L ('IrqDrv: DeviceInstallDisabled=' + $orig)
        try { Set-ItemProperty $k -Name DeviceInstallDisabled -Value 0 -Type DWord -ErrorAction Stop } catch { L ('IrqDrv: cannot clear DeviceInstallDisabled: ' + $_) }
        New-Item -ItemType Directory -Force C:\rm9\irq | Out-Null
        foreach ($f in 'rm9irq.sys', 'rm9irq.inf', 'rm9irq.cat') { Copy-Item ('S:\rm9\irqpkg\' + $f) ('C:\rm9\irq\' + $f) -Force; L ('IrqDrv: copied ' + $f + ' ' + (Get-Item ('C:\rm9\irq\' + $f)).Length) }
        Copy-Item S:\rm9\irqinstall.ps1 C:\rm9\link\irqinstall.ps1 -Force
        Remove-Item C:\rm9\irq\install.log -ErrorAction SilentlyContinue
        L 'IrqDrv: about to run irqinstall.ps1'
        $irqArgs = @(); if (Test-Path S:\rm9\irqacpi.flag) { $irqArgs = @('-Acpi'); L 'IrqDrv: ACPI mode (ACPI\RM9I0001 of Mu-pcie-rp5)' }
        & powershell -NoProfile -ExecutionPolicy Bypass -File C:\rm9\link\irqinstall.ps1 @irqArgs *> C:\rm9\irq\install_out.txt
        Get-Content C:\rm9\irq\install.log -ErrorAction SilentlyContinue | ForEach-Object { L ('IrqDrv install.log: ' + $_) }
        if ($orig -ne $null) { try { Set-ItemProperty $k -Name DeviceInstallDisabled -Value $orig -Type DWord } catch { } }
        foreach ($x in (Get-PnpDevice -ErrorAction SilentlyContinue | Where-Object { $_.HardwareID -contains 'ROOT\RM9IRQ' -or $_.InstanceId -like 'ACPI\RM9I0001*' })) {
            $pc = (Get-PnpDeviceProperty -InstanceId $x.InstanceId -KeyName 'DEVPKEY_Device_ProblemCode' -ErrorAction SilentlyContinue).Data
            L ('IrqDrv pnp: ' + $x.Status + ' | problem code ' + $pc + ' | ' + $x.InstanceId)
            foreach ($ln in (& pnputil.exe /enum-devices /instanceid $x.InstanceId /resources 2>&1)) { L ('  pnputil: ' + $ln) }
        }
        L ('IrqDrv: rm9irq service: ' + ((& sc.exe query rm9irq 2>&1) -join ' '))
        L 'IrqDrv: starting a ping for 16 s'
        $pg = Start-Process ping.exe -ArgumentList '-n', '40', '-w', '500', '-l', '1000', '192.168.x.x' -PassThru -WindowStyle Hidden
        for ($j = 0; $j -lt 16; $j++) { Start-Sleep -Milliseconds 1000; DbgFlush }
        try { if ($pg -and -not $pg.HasExited) { $pg.Kill() } } catch { }
        DbgFlush
        L 'IrqDrv: done (see RM9IRQ lines in dbgcap.txt)'
    } catch { L ('IrqDrvTest failed: ' + $_) }
}
function KickFlags([int]$burst = -1, [int]$tail = -1) {
    # flags word for DbgIrq mode 4: bit 0 = start, bits 8..15 = burst period ms, bits 16..31 = tail ms (no arguments: read S:\rm9\kick.flag "<burst> <tail>")
    if ($burst -lt 0) {
        $burst = 0; $tail = 0
        try { $x = @((Get-Content S:\rm9\kick.flag -TotalCount 1) -split '\s+' | Where-Object { $_ -ne '' }); if ($x.Count -ge 2) { $burst = [int]$x[0]; $tail = [int]$x[1] } } catch { }
    }
    return [uint32](1 -bor ($burst -shl 8) -bor ($tail -shl 16))
}
function KickSpeedTest() {
    # S:\rm9\kickspeed.flag (with the ACPI device + rm9irq): throughput of the polling schemes on the same connection - 20 MB downloads and a ping run for each:
    #   P: poll every 10 ms, no kick (the old scheme)   K: poll 1000 ms + kick   B1: + follow-up poll every 5 ms until 150 ms after the last interrupt   B2: every 2 ms until 300 ms.   The kick.flag setting is restored at the end.
    try {
        if (-not $script:dbgOn) { L 'KickSpeed: no dbgcap'; return }
        $base = $script:qcBase
        $cfgs = @(@('S1 poll 1000 ms + kick + 5 ms/30 ms', 1000, (KickFlags 5 30)), @('S2 poll 1000 ms + kick + 5 ms/20 ms', 1000, (KickFlags 5 20)), @('S3 poll 1000 ms + kick + 10 ms/30 ms', 1000, (KickFlags 10 30)), @('S4 poll 1000 ms + kick + 8 ms/25 ms', 1000, (KickFlags 8 25)), @('B4 poll 1000 ms + kick + 3 ms/50 ms', 1000, (KickFlags 3 50)))
        foreach ($c in $cfgs) {
            [void](DbgIrq 4 0 0 0)
            [void](DbgPoll $base 0)
            Start-Sleep -Milliseconds 500
            $pp = DbgPoll $base $c[1]
            if ($c[2]) { $r = DbgIrq 4 0 0 ([uint32]$c[2]); L ('KickSpeed [' + $c[0] + ']: kick thread status ' + ('{0:X8}' -f $r[15])) }
            Start-Sleep -Seconds 3
            $r0 = DbgIrq 2 0 0 0
            for ($k = 0; $k -lt 2; $k++) {
                try {
                    $sw = [Diagnostics.Stopwatch]::StartNew(); $wc = New-Object Net.WebClient
                    $b = $wc.DownloadData('http://speed.cloudflare.com/__down?bytes=20000000'); $sw.Stop()
                    L ('KickSpeed [' + $c[0] + '] download ' + $b.Length + ' bytes in ' + [Math]::Round($sw.Elapsed.TotalSeconds, 1) + ' s = ' + [Math]::Round($b.Length * 8 / 1e6 / $sw.Elapsed.TotalSeconds, 1) + ' Mbit/s')
                } catch { L ('KickSpeed [' + $c[0] + '] download failed: ' + $_.Exception.Message) }
            }
            $o = (& ping.exe -n 8 -w 2000 -l 1000 192.168.x.x 2>&1 | Out-String) -split "`r?`n"
            $r1 = DbgIrq 2 0 0 0
            foreach ($ln in $o) { if ($ln -match 'Packets:|Minimum') { L ('KickSpeed [' + $c[0] + '] ping: ' + $ln.Trim()) } }
            # idle cost: 15 s without traffic - how many interrupts / follow-up polls does the chip still cause?
            $d0 = DbgIrq 2 0 0 0; Start-Sleep -Seconds 15; $d1 = DbgIrq 2 0 0 0
            L ('KickSpeed [' + $c[0] + '] IDLE 15 s: event wakes ' + ($d1[69] - $d0[69]) + '  burst polls ' + ($d1[66] - $d0[66]))
            L ('KickSpeed [' + $c[0] + ']: poll DPC kicks ' + $r0[32] + ' -> ' + $r1[32] + '  event wakes ' + $r0[69] + ' -> ' + $r1[69] + '  burst polls ' + $r0[66] + ' -> ' + $r1[66])
            DbgFlush
        }
        [void](DbgIrq 4 0 0 0)
        [void](DbgPoll $base 0)
        Start-Sleep -Milliseconds 500
        $pp = DbgPoll $base $script:pollMs
        if (Test-Path S:\rm9\kick.flag) { $r = DbgIrq 4 0 0 (KickFlags); L ('KickSpeed: restored poll ' + $script:pollMs + ' ms + kick, status ' + ('{0:X8}' -f $r[15])) } else { L ('KickSpeed: restored poll ' + $script:pollMs + ' ms') }
        L 'KickSpeed: done'
    } catch { L ('KickSpeedTest failed: ' + $_) }
}
function IrqKickTest() {
    # S:\rm9\irqkick.flag (needs the ACPI device + rm9irq of IrqDrvTest and the dbgcap with IRQ mode 4, NEXT.md 0be): is the poll really driven by the chip's interrupts?  Same ping at three settings:
    #   A: poll every 1000 ms, no kick   B: poll every 1000 ms + kick thread (rm9irq ISR -> DPC -> event -> poll DPC)   C: poll every 5000 ms + kick thread.   Normal setting (pollMs) is restored at the end.
    try {
        if (-not $script:dbgOn) { L 'IrqKick: no dbgcap'; return }
        $base = $script:qcBase
        $cfgs = @(@('A poll 1000 ms, no kick', 1000, 0), @('B poll 1000 ms + kick', 1000, 1), @('C poll 5000 ms + kick', 5000, 1), @('D poll 1000 ms, no kick (again)', 1000, 0))
        foreach ($c in $cfgs) {
            [void](DbgIrq 4 0 0 0)
            [void](DbgPoll $base 0)
            Start-Sleep -Milliseconds 500
            $pp = DbgPoll $base $c[1]
            if ($c[2]) { $r = DbgIrq 4 0 0 1; L ('IrqKick [' + $c[0] + ']: kick thread status ' + ('{0:X8}' -f $r[15])) }
            Start-Sleep -Seconds 3
            $r0 = DbgIrq 2 0 0 0
            $o = (& ping.exe -n 15 -w 3000 -l 1000 192.168.x.x 2>&1 | Out-String) -split "`r?`n"
            $r1 = DbgIrq 2 0 0 0
            foreach ($ln in $o) { if ($ln -match 'Packets:|Minimum|timed out|unreachable|Reply from.*time') { L ('IrqKick [' + $c[0] + '] ping: ' + $ln.Trim()) } }
            L ('IrqKick [' + $c[0] + ']: poll DPC kicks ' + $r0[32] + ' -> ' + $r1[32] + '  event wakes ' + $r0[69] + ' -> ' + $r1[69])
            DbgFlush
        }
        [void](DbgIrq 4 0 0 0)
        [void](DbgPoll $base 0)
        Start-Sleep -Milliseconds 500
        $pp = DbgPoll $base $script:pollMs; L ('IrqKick: polling restored (' + $script:pollMs + ' ms) ' + (Hx $pp))
        L 'IrqKick: done'
    } catch { L ('IrqKickTest failed: ' + $_) }
}
function IrqTest() {
    # S:\rm9\irqtest.flag + p8 + a dbgcap.sys with IOCTL 0xA09 (SPI connect): stage 1 of interrupt-driven Wi-Fi.  Connect SPIs 800..811 (chip ring MSIs arrive there, SpiProbe/NEXT.md 0az) with IoConnectInterruptEx,
    # ISR only counts; ping generates ring activity.  Watch whether the HAL accepts the connection (status per line) and whether the per-line counters move.  Mode 1 flag bit 0 = also kick the poll DPC (stage 2).
    try {
        if (-not $script:dbgOn) { L 'IrqTest: no dbgcap'; return }
        L 'IrqTest: about to connect SPIs 800..811'
        $r = DbgIrq 1 800 12 0
        if (-not $r) { L 'IrqTest: DbgIrq failed (no IOCTL 0xA09 in this dbgcap.sys?)'; return }
        L ('IrqTest: connect status per line ' + ((16..27 | ForEach-Object { '{0:X8}' -f $r[$_] }) -join ' '))
        L ('IrqTest: PCI PDOs found ' + $r[66] + ', chosen irql ' + $r[67] + ', combo ' + $r[68] + ', matrix (pdo x irql 3..12) ' + ((34..65 | ForEach-Object { '{0:X8}' -f $r[$_] }) -join ' '))
        $pg = Start-Process ping.exe -ArgumentList '-n', '40', '-w', '500', '-l', '1000', '192.168.x.x' -PassThru -WindowStyle Hidden
        for ($k = 0; $k -lt 14; $k++) {
            Start-Sleep -Milliseconds 1000
            $r = DbgIrq 2 0 0 0
            L ('IrqTest t=' + ($k + 1) + ' s: counts ' + ((0..11 | ForEach-Object { $r[$_] }) -join ',') + ' kicks ' + $r[32])
        }
        try { if ($pg -and -not $pg.HasExited) { $pg.Kill() } } catch { }
        L 'IrqTest: about to disconnect'
        $r = DbgIrq 0 0 0 0
        L ('IrqTest: disconnected, final counts ' + ((0..11 | ForEach-Object { $r[$_] }) -join ','))
    } catch { L ('IrqTest failed: ' + $_) }
}
function SpiProbe() {
    # S:\rm9\spiprobe.flag + qcwlan_patched.sys = p8 (ring MSIs -> GIC MBI frame, data = INTID 800 + vector) + a dbgcap.sys with HPPIR mode 5 (dbgcap.c "SPI window").
    # MbiRing saw nothing in ISPENDR with the SPIs disabled - but a physical SPI is probably only enabled in the real GIC once the guest enables it.  So inside a HIGH_LEVEL window on CPU 0 (the SPIs' default route) dbgcap
    # enables INTID 800..815 in the virtual GICD, watches ICC_HPPIR1 for 200 ms, reads ISPENDR back, then disables them and clears the pending state before the IRQL drops: Windows never takes them.
    # DON'T point mode 5 at a word that holds a live device SPI (the UFS SPI 297 is word 9): the window switches the bits off again at the end.
    try {
        if (-not $script:dbgOn) { L 'SpiProbe: no dbgcap'; return }
        $pg = Start-Process ping.exe -ArgumentList '-n', '80', '-w', '500', '-l', '1000', '192.168.x.x' -PassThru -WindowStyle Hidden
        Start-Sleep -Milliseconds 800
        for ($k = 0; $k -lt 25; $k++) {
            L ('SpiProbe: about to open the SPI window #' + $k)
            $res = DbgHppir 0 5 25 0xFFFF 200000
            if ($res) { L ('SpiProbe #' + $k + ': ran on ' + $res[0] + ' seen ' + $res[1] + ' ids=' + (($res[2..9] | ForEach-Object { '{0:X}' -f $_ }) -join ',') + ' before=' + ('{0:X}' -f $res[10]) + ' ISPENDR[25]=' + ('{0:X8}' -f $res[14]) + ' ISENABLER[25]=' + ('{0:X8}' -f $res[15]) + ' RPR=' + ('{0:X}' -f $res[11]) + ' PMR=' + ('{0:X}' -f $res[13])) } else { L ('SpiProbe #' + $k + ': DbgHppir failed') }
            Start-Sleep -Milliseconds 300
        }
        try { if ($pg -and -not $pg.HasExited) { $pg.Kill() } } catch { }
        L ('SpiProbe: after, GICD word 25 en=' + ('{0:X8}' -f (Rm9Read ((A '17100000') + 0x100 + 100) 1)[0]) + ' pend=' + ('{0:X8}' -f (Rm9Read ((A '17100000') + 0x200 + 100) 1)[0]))
    } catch { L ('SpiProbe failed: ' + $_) }
}
function MbiRing() {
    # S:\rm9\mbiring.flag + S:\rm9\qcwlan_patched.sys = p8 (drivers\wcn7850_x\patch_mbi.py): the chip's SRNG ring MSIs go to the GIC MBI frame 0x17110040 with data = INTID 800 + vector.
    # Does a chip-originated MBI write become a pending SPI in the VM?  Watch the virtual GICD ISPENDR / ISENABLER / ISACTIVER words for INTID 800..831 (word 25) and 832..863 (word 26) while a ping runs;
    # word 9 (INTID 288..319) holds the UFS SPI 297 (bit 9) as a control that this way of looking sees a real device SPI.  The SPIs stay disabled in the GICD, so Windows never takes them.
    try {
        $gd = A '17100000'
        function Snap() {
            $o = @()
            foreach ($w in 9, 25, 26) { $o += ('w' + $w + ' en=' + ('{0:X8}' -f (Rm9Read ($gd + 0x100 + 4 * $w) 1)[0]) + ' pend=' + ('{0:X8}' -f (Rm9Read ($gd + 0x200 + 4 * $w) 1)[0]) + ' act=' + ('{0:X8}' -f (Rm9Read ($gd + 0x300 + 4 * $w) 1)[0])) }
            $o -join ' | '
        }
        L ('MbiRing: baseline ' + (Snap))
        $pg = Start-Process ping.exe -ArgumentList '-n', '60', '-w', '500', '-l', '1000', '192.168.x.x' -PassThru -WindowStyle Hidden
        $last = ''
        for ($k = 0; $k -lt 48; $k++) {
            Start-Sleep -Milliseconds 250
            $s = Snap
            if ($s -ne $last) { L ('MbiRing t=' + ($k * 0.25) + ' s: ' + $s); $last = $s }
        }
        try { if ($pg -and -not $pg.HasExited) { $pg.Kill() } } catch { }
        L ('MbiRing: final ' + (Snap))
    } catch { L ('MbiRing failed: ' + $_) }
}
function HppirCpu0() {
    # S:\rm9\hppir0.flag (2026-10-30): watch ICC_HPPIR1_EL1 (highest priority PENDING interrupt, nothing acknowledged / EOI'd) on CPU 0 = the redistributor the collection is mapped to, while a software INT (dev 0x1401) is raised.
    # Earlier HPPIR watches ran on CPU 3 / 5 only (not the INT's target).  IarCpu0 (manual IAR+EOIR on CPU 0) froze Windows; this one consumes nothing.  CPU 3 first as the control, every step logged BEFORE it runs.
    # A background ping makes the chip raise its own MSIs too (mode 0 = just watch).
    try {
        if (-not $script:dbgOn) { L 'HppirCpu0: no dbgcap'; return }
        $pg = Start-Process ping.exe -ArgumentList '-n', '60', '-w', '500', '192.168.x.x' -PassThru -WindowStyle Hidden
        Start-Sleep -Milliseconds 800
        foreach ($cpu in 3, 0) {
            $steps = @(@(0, 0, 0, 200000, 'watch 200 ms (chip MSIs from ping)'), @(1, 0, 0, 50000, 'SGI1 to self'))
            foreach ($ev in 0, 2, 4, 7, 9, 2) { $steps += , @(2, 0x1401, $ev, 50000, ('ITS INT dev 0x1401 ev ' + $ev)) }
            foreach ($s in $steps) {
                L ('HppirCpu0: about to run CPU ' + $cpu + ' ' + $s[4])
                $res = DbgHppir $cpu $s[0] $s[1] $s[2] $s[3]
                if ($res) { L ('HppirCpu0 CPU ' + $cpu + ' [' + $s[4] + ']: ran on ' + $res[0] + ' seen ' + $res[1] + ' ids=' + (($res[2..9] | ForEach-Object { '{0:X}' -f $_ }) -join ',') + ' before=' + ('{0:X}' -f $res[10]) + ' RPR=' + ('{0:X}' -f $res[11]) + ' AP1R0=' + ('{0:X}' -f $res[12]) + ' PMR=' + ('{0:X}' -f $res[13]) + ' cw=' + ('{0:X}' -f $res[14]) + ' cr=' + ('{0:X}' -f $res[15])) } else { L ('HppirCpu0 CPU ' + $cpu + ' [' + $s[4] + ']: DbgHppir failed') }
                Start-Sleep -Milliseconds 300
            }
        }
        try { if ($pg -and -not $pg.HasExited) { $pg.Kill() } } catch { }
    } catch { L ('HppirCpu0 failed: ' + $_) }
}
function IntTest() {
    # S:\rm9\inttest.flag: do real interrupts reach the driver now that the ITS mapping for dev 0x1401 exists?  All polling is stopped for 2 x ~14 s (the monitor restarts it on its next pass); the driver's ISR counters
    # (KReadVa image+0x390A00) are read around a ping to the gateway.  Counters that move while nothing polls = real MSIs.
    try {
        if (-not $script:dbgOn -or -not $script:qcBase) { L 'IntTest: no dbgcap / driver base'; return }
        # which interrupt resources did Windows hand to the endpoint?  (IRQ numbers; a message-signaled device shows its message count)
        try {
            $epid = (Get-PnpDevice | Where-Object { $_.InstanceId -like 'PCI*VEN_17CB&DEV_1107*' } | Select-Object -First 1).InstanceId
            L ('IntTest endpoint: ' + $epid)
            $res = pnputil.exe /enum-devices /instanceid "$epid" /resources 2>&1
            foreach ($ln in $res) { L ('  pnputil: ' + $ln) }
            $pa = Get-CimInstance Win32_PnPAllocatedResource | Where-Object { $_.Dependent.DeviceID -like '*VEN_17CB&DEV_1107*' }
            foreach ($r in $pa) { L ('  alloc: ' + $r.Antecedent.CimClass.CimClassName + ' ' + (($r.Antecedent.CimInstanceProperties | ForEach-Object { $_.Name + '=' + $_.Value }) -join ' ')) }
            L ('  alloc count: ' + @($pa).Count)
        } catch { L ('IntTest resource query failed: ' + $_) }
        for ($k = 0; $k -lt 2; $k++) {
            $pp = DbgPoll $script:qcBase 0; L ('IntTest ' + $k + ': polling stopped ' + (Hx $pp))
            Start-Sleep 2
            if ($k -eq 0) {
                # software INT for dev 0x1401 events 2..5, 8 (kernel-side ITS command, no chip involved) while nothing polls: if the driver's ISR counter of that id moves, ITS -> redistributor -> Windows' handler works
                # the production hypervisor copies the guest's LPI configuration table only once (first EnableLPIs=1); a later change needs GICR_INVLPIR / INVALLR (redistributor 0 RD frame +0xA0 / +0xB0): ask for a re-copy of LPIs 0x2000..0x200F
                if (Test-Path S:\rm9\invlpir.flag) {
                    $grx = A '17180000'
                    for ($lp = 0x2000; $lp -lt 0x2010; $lp++) { Rm9Write ($grx + 0xA0) ([uint32]$lp); Start-Sleep -Milliseconds 20 }
                    Rm9Write ($grx + 0xB0) 0
                    Start-Sleep -Milliseconds 200
                    L ('IntTest: GICR0 INVLPIR 0x2000..0x200F + INVALLR written; GICR0.CTLR=' + ('{0:X8}' -f (Rm9Read $grx 1)[0]) + ' ' + (State))
                }
                # first re-send INV (re-read the LPI configuration byte) for every event, then SYNC: the vITS caches the enable bit at MAPTI / INV time, and Windows may have written the table after its own INVs
                for ($e2 = 0; $e2 -lt 16; $e2++) { [void](QCmd ([uint32[]]@(0xC, 0x1401, $e2, 0, 0, 0, 0, 0))) }
                [void](QCmd ([uint32[]]@(5, 0, 0, 0, 0, 0, 0, 0)))
                L ('IntTest: extra INV x16 + SYNC sent ' + (State))
                foreach ($ev in 0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10) {
                    $h0 = KReadVa ($script:qcBase + 0x42B840) 64
                    $c0 = KReadVa ($script:qcBase + 0x390A00 + 4 * $ev) 4
                    $ok = QCmd ([uint32[]]@(3, 0x1401, $ev, 0, 0, 0, 0, 0))
                    Start-Sleep -Milliseconds 300
                    $c1 = KReadVa ($script:qcBase + 0x390A00 + 4 * $ev) 4
                    $h1 = KReadVa ($script:qcBase + 0x42B840) 64
                    L ('IntTest INT ev ' + $ev + ': sent=' + $ok + ' counter ' + (HexB $c0) + ' -> ' + (HexB $c1) + '  ISRhits ' + (HexB $h0) + ' -> ' + (HexB $h1) + '  ' + (State))
                }
            }
            if ($k -eq 0) {
                # INT burst: 3 x 90 software INTs for dev 0x1401 event 2 (LPI 0x2002) inside ~1 s, with Windows' own interrupt count (perf raw counter) read around it; control = same window without INTs
                function IntRaw() { (Get-CimInstance Win32_PerfRawData_Counters_ProcessorInformation -Filter "Name='_Total'").InterruptsPersec }
                function IntBurst([int]$ev, [int]$n) {
                    $cw0 = Its32 0x88; $cr0 = Its32 0x90
                    if ($cw0 -ne $cr0) { return 'queue busy' }
                    for ($i = 0; $i -lt $n; $i++) {
                        $slot = [uint64](($cw0 + 0x20 * $i) -band 0xFFF)
                        $x = @(3, 0x1401, $ev, 0, 0, 0, 0, 0)
                        for ($j = 0; $j -lt 8; $j++) { Rm9Write ($q + $slot + 4 * $j) ([uint32]$x[$j]) }
                    }
                    Rm9Write ($its + 0x88) ([uint32](($cw0 + 0x20 * $n) -band 0xFFF))
                    for ($t = 0; $t -lt 100; $t++) { Start-Sleep -Milliseconds 5; if ((Its32 0x90) -eq (Its32 0x88)) { break } }
                    return (State)
                }
                $r0 = IntRaw; Start-Sleep -Milliseconds 1000; $r1 = IntRaw
                L ('IntTest control (1 s, no INT): interrupts ' + ($r1 - $r0))
                for ($b = 0; $b -lt 3; $b++) {
                    $c0 = KReadVa ($script:qcBase + 0x390A00 + 4 * 2) 4
                    $r0 = IntRaw; $st = IntBurst 2 90; Start-Sleep -Milliseconds 500; $r1 = IntRaw
                    $c1 = KReadVa ($script:qcBase + 0x390A00 + 4 * 2) 4
                    L ('IntTest burst ' + $b + ' (90 INT ev 2): interrupts ' + ($r1 - $r0) + '  counter ' + (HexB $c0) + ' -> ' + (HexB $c1) + '  ' + $st)
                }
            }
            $a0 = HexB (KReadVa ($script:qcBase + 0x390A00) 64)
            L ('IntTest ' + $k + ': ISR before=' + $a0)
            RunTo 'ping.exe' '-n 8 -w 1500 192.168.x.x' 14000
            $a1 = HexB (KReadVa ($script:qcBase + 0x390A00) 64)
            L ('IntTest ' + $k + ': ISR after =' + $a1 + '  changed=' + ($a0 -ne $a1))
            LpiState ('inttest' + $k)
            $pp = DbgPoll $script:qcBase $script:pollMs; L ('IntTest ' + $k + ': polling restarted ' + (Hx $pp))
            Start-Sleep 5
        }
    } catch { L ('IntTest failed: ' + $_) }
}
function SendInt([string]$why) {
    # interrupt-delivery diagnostics (writes ITS commands and reads ITS/GIC registers that freeze the bus): only with S:\rm9\itsdiag.flag.  2026-10-29: the third no-cleanup run stopped right here (+16 s, ItsDump)
    if (-not (Test-Path S:\rm9\itsdiag.flag)) { return }
    # INT (dev 0x1401, event 0) followed by INVALL (collection 0) and SYNC (RDbase 0): the latter two make the ITS re-read the LPI configuration in the redistributor and complete the delivery
    $cw0 = Its32 0x88; $cr0 = Its32 0x90
    if ($cw0 -ne $cr0) { L ('  INT(' + $why + ') skipped: queue busy ' + (State)); return }
    $slot = [uint64]($cw0 -band (U 'FFFFFFFE'))
    $cmds = @(@(3, 0x1401, 0, 0, 0, 0, 0, 0), @(0x0D, 0, 0, 0, 0, 0, 0, 0), @(5, 0, 0, 0, 0, 0, 0, 0))
    $n = 0
    foreach ($c in $cmds) {
        [uint32[]]$x = $c
        $o = ($slot + 0x20 * $n) -band 0xFFF
        for ($i = 0; $i -lt 8; $i++) { Rm9Write ($q + $o + 4 * $i) $x[$i] }
        $n++
    }
    Rm9Write ($its + 0x88) ([uint32](($slot + 0x20 * $n) -band 0xFFF))
    Start-Sleep -Milliseconds 100
    L ('  INT+INVALL+SYNC(' + $why + ') -> ' + (State))
    LpiState ('after ' + $why)
    if ($why -eq '+2s' -or $why -eq '+16s') { ItsDump $why }
    if ($why -eq '+2s') { CpuInfo; GicrProbe; GicDump }
    if ($why -eq '+4s') { HppirSweep }
}
function HexB($b) { if (-not $b) { return 'null' }; (($b | ForEach-Object { '{0:X2}' -f $_ }) -join '') }
function IsrWatch() {
    # driver-internal ISR bookkeeping (isr_record counters per message id, and a few globals next to the log threshold), read by kernel virtual address through dbgcap.sys
    if (-not $script:dbgOn) { return }
    if (-not $script:qcBase) {
        $script:qcBase = KModBase 'qcwlanhmt8380.sys'
        if ($script:qcBase) {
            L ('  qcwlanhmt8380.sys base ' + ('{0:X}' -f $script:qcBase))
            # S:\rm9\pollms.txt: poll period in ms (default 10); a shorter period gives the HTC credits and the received frames back sooner (speed test, 2026-10-29)
            $script:pollMs = 10
            if (Test-Path S:\rm9\pollms.txt) { try { $script:pollMs = [int](Get-Content S:\rm9\pollms.txt -TotalCount 1) } catch { } }
            $pp = DbgPoll $script:qcBase $script:pollMs
            L ('  MHI event-ring poll (dbgcap work items, ' + $script:pollMs + ' ms) started: ' + (Hx $pp))
            # S:\rm9\kick.flag: interrupt-driven mode (NEXT.md 0bf): the chip's MSIs (SPIs of the ACPI device RM9I0001, rm9irq.sys) wake the poll through the event \BaseNamedObjects\Rm9IrqKick, so pollms.txt only
            # has to hold a slow safety period (1000).  Needs Mu-pcie-rp5, the installed rm9irq (IrqDrvTest -Acpi once) and p8.
            # kick.flag may hold "<burst ms> <tail ms>": after an interrupt keep polling every <burst> ms until <tail> ms have passed without another one (NAPI-like)
            if (Test-Path S:\rm9\kick.flag) { try { $kf = KickFlags; $kr = DbgIrq 4 0 0 $kf; L ('  kick thread (interrupt-driven poll, flags ' + ('{0:X8}' -f $kf) + '): status ' + ('{0:X8}' -f $kr[15])) } catch { L ('  kick thread failed: ' + $_) } }
        }
        return
    }
    $pp = DbgPoll $script:qcBase $script:pollMs
    if ($pp) { $pk = 'runs=' + $pp[0] + ' withCtx=' + $pp[1] + ' ctxlo=' + ('{0:X8}' -f $pp[2]) + ' bh=' + $pp[3]; if (($pk -ne $script:pollPrev) -and (((Get-Date) - $script:pollAt).TotalSeconds -gt 5)) { $script:pollPrev = $pk; $script:pollAt = Get-Date; L ('  MHI poll: ' + $pk) } }
    $a = KReadVa ($script:qcBase + 0x390A00) 64
    $g = KReadVa ($script:qcBase + 0x3BB030) 32
    $x = (HexB $a) + ' / ' + (HexB $g)
    if (($x -ne $script:isrPrev) -and (((Get-Date) - $script:isrAt).TotalSeconds -gt 5)) { $script:isrPrev = $x; $script:isrAt = Get-Date; L ('  ISR counters[0..15]=' + (HexB $a) + ' glob3bb030=' + (HexB $g)) }
}
function Pump([int]$sec, [string]$tag) {
    $prev = ''; $n = 0; $t0 = Get-Date
    while (((Get-Date) - $t0).TotalSeconds -lt $sec) {
        DbgFlush
        $s = State
        if ($s -ne $prev) { $prev = $s; $n++; if ($n -le 400) { L ("$tag $s") } }
        $cr = Its32 0x90
        if (($cr -band 1) -and -not $handled.ContainsKey($cr)) { $handled[$cr] = 1; [void](Fix $cr) }
        if ($tag -eq 'ep') {
            if (-not $script:reverted -and ((((Get-Date) - $t0).TotalMilliseconds -gt 1500) -or ((sc.exe query qcwlan) -match 'RUNNING'))) {
                sc.exe config qcwlan start= disabled | Out-Null; $script:reverted = $true; L '  qcwlan Start put back to 4 (driver is loaded)'
            }
            if (-not $script:msiRedirected) {
                $mc = (Rm9Read ($ecamB + 0x50) 1)[0]
                if (($mc -band 0x10000) -ne 0) {
                    $script:msiRedirected = $true; $script:intAt = Get-Date; $script:intDone = @{}
                    Start-Sleep -Milliseconds 300
                    L ('  ITT @FFEB9000: ' + (Hx (Rm9Read (A 'FFEB9000') 8)))
                    $cw0 = Its32 0x88; $cr0 = Its32 0x90
                    for ($o = 0; $o -lt $cw0; $o += 0x20) { $c = Rm9Read ($q + $o) 8; L ('  Q[' + ('{0:X3}' -f $o) + '] op=' + ('{0:X2}' -f ($c[0] -band 0xFF)) + ' ' + (Hx $c[0..5])) }
                    if ($cw0 -eq $cr0) {
                        $slot = [uint64]($cw0 -band (U 'FFFFFFFE'))
                        [uint32[]]$x = @(3, 0x1401, 0, 0, 0, 0, 0, 0); for ($i = 0; $i -lt 8; $i++) { Rm9Write ($q + $slot + 4 * $i) $x[$i] }; L ('  cmd written: ' + (Hx (Rm9Read ($q + $slot) 8)))
                        Rm9Write ($its + 0x88) ([uint32](($slot + 0x20) -band 0xFFF))
                        Start-Sleep -Milliseconds 100
                        L ('  INT dev 0x1401 ev 0 issued at slot ' + ('{0:X}' -f $slot) + ' -> ' + (State) + ' ITT now: ' + (Hx (Rm9Read (A 'FFEB9000') 8)))
                        $gr_ = A '17180000'
                        $pb_ = [uint64]((Rm9Read ($gr_ + 0x70) 1)[0] -band (U 'FFFFF000')); $pq_ = [uint64]((Rm9Read ($gr_ + 0x78) 1)[0] -band (U 'FFFF0000'))
                        for ($t = 0; $t -lt 4; $t++) {
                            Start-Sleep -Milliseconds 150
                            L ('  after INT +' + ($t * 150 + 150) + 'ms: LPIcfg[0x2010..0x201F]=' + (Hx (Rm9Read ($pb_ + 0x10) 4)) + ' pending[0x2000..0x203F]=' + (Hx (Rm9Read ($pq_ + 0x400) 2)) + ' GICR0.CTLR=' + ('{0:X8}' -f (Rm9Read $gr_ 1)[0]))
                        }
                    } else { L ('  INT skipped: queue busy ' + (State)) }
                }
            }
            if ($script:intAt) {
                $dt = ((Get-Date) - $script:intAt).TotalSeconds
                foreach ($k in @(2, 4, 7, 11, 16)) { if (($dt -gt $k) -and -not $script:intDone[$k]) { $script:intDone[$k] = $true
                    if ($false) { ItsDiff } else { SendInt ('+' + $k + 's') } } }
            }
            IsrWatch
            EpWatch
        }
    }
    L ("$tag pump end, state changes=$n " + (State))
}
$ecamB = A '60100000'
$script:qcBase = 0; $script:isrAt = Get-Date; $script:pollAt = Get-Date; $script:isrPrev = ''; $script:msiRedirected = $false; $script:reverted = $false; $script:fsrPrev = '#'; $script:mhiPrev = ''; $script:epPrev = ''; $script:mhiAt = Get-Date
function EpWatch() {
    $cmd = (Rm9Read ($ecamB + 4) 1)[0]; $b0 = (Rm9Read ($ecamB + 0x10) 1)[0]; $b1 = (Rm9Read ($ecamB + 0x14) 1)[0]
    $x = 'cmd=' + ('{0:X8}' -f $cmd) + ' bar0=' + ('{0:X8}' -f $b1) + ':' + ('{0:X8}' -f $b0) + ' msi=' + ('{0:X8}' -f (Rm9Read ($ecamB + 0x50) 1)[0]) + ',' + ('{0:X8}' -f (Rm9Read ($ecamB + 0x54) 1)[0]) + ',' + ('{0:X8}' -f (Rm9Read ($ecamB + 0x5C) 1)[0]) + ' lnk=' + ('{0:X8}' -f (Rm9Read ($ecamB + 0x80) 1)[0])
    if ($x -ne $script:epPrev) { $script:epPrev = $x; L ("  EP $x") }
    $base = [uint64]($b0 -band (U 'FFFFFFF0')) + ([uint64]$b1 * 4294967296)
    if ((($cmd -band 2) -ne 0) -and ($base -ge (A '60200000')) -and ($base -lt (A '62000000')) -and (((Get-Date) - $script:mhiAt).TotalMilliseconds -gt 100)) {
        $script:mhiAt = Get-Date
        $v = New-Object 'System.Collections.Generic.List[string]'
        foreach ($off in 0x0, 0x10, 0x38, 0x48, 0x28, 0x2C) { $v.Add(('{0:X8}' -f (Rm9Read ($base + $off) 1)[0])) }
        $bo = [Convert]::ToUInt32($v[4], 16)
        $x2 = 'MHIVER=' + $v[0] + ' MHICFG=' + $v[1] + ' MHICTRL=' + $v[2] + ' MHISTATUS=' + $v[3] + ' BHIOFF=' + $v[4]
        if ($bo -gt 0 -and $bo -lt 0x10000 -and (($bo -band 3) -eq 0)) {
            $bh = $base + $bo
            $w = Rm9Read $bh 20     # BHI regs 0x00..0x4F
            $x2 += ' | BHI ver=' + ('{0:X8}' -f $w[1]) + ' IMGADDR=' + ('{0:X8}' -f $w[3]) + ':' + ('{0:X8}' -f $w[2]) + ' IMGSIZE=' + ('{0:X8}' -f $w[4]) + ' EXECENV=' + ('{0:X8}' -f $w[10]) + ' STATUS=' + ('{0:X8}' -f $w[11]) + ' ERRCODE=' + ('{0:X8}' -f $w[12]) + ' ERRDBG=' + ('{0:X8}' -f $w[13]) + ',' + ('{0:X8}' -f $w[14]) + ',' + ('{0:X8}' -f $w[15]) + ' SERIAL=' + ('{0:X8}' -f $w[16])
        }
        $rw = Rm9Read $base 32
        $x2 += ' | RAW00=' + (Hx $rw)
        foreach ($dbo in @($rw[6], $rw[8])) { if (($dbo -gt 0) -and ($dbo -lt 0x10000) -and (($dbo -band 3) -eq 0)) { $x2 += ' | DB@' + ('{0:X}' -f $dbo) + '=' + (Hx (Rm9Read ($base + $dbo) 8)) } }
        $be = [Convert]::ToUInt32($v[5], 16)
        if ($be -gt 0 -and $be -lt 0x10000 -and (($be -band 3) -eq 0)) {
            $e = Rm9Read ($base + $be) 29
            $x2 += ' | BHIE@' + $v[5] + ' TXVEC=' + ('{0:X8}' -f $e[12]) + ':' + ('{0:X8}' -f $e[11]) + ' size=' + ('{0:X8}' -f $e[13]) + ' db=' + ('{0:X8}' -f $e[14]) + ' st=' + ('{0:X8}' -f $e[15]) + ' RXVEC=' + ('{0:X8}' -f $e[25]) + ':' + ('{0:X8}' -f $e[24]) + ' size=' + ('{0:X8}' -f $e[26]) + ' db=' + ('{0:X8}' -f $e[27]) + ' st=' + ('{0:X8}' -f $e[28])
        }
        # MHI context bases the driver programmed (0x58 CCABAP, 0x60 ECABAP) and, if they point into DRAM, event ring 0's context (ring base / length / read ptr / write ptr)
        $m = Rm9Read ($base + 0x58) 12
        $x2 += ' | CCABAP=' + ('{0:X8}' -f $m[1]) + ':' + ('{0:X8}' -f $m[0]) + ' ECABAP=' + ('{0:X8}' -f $m[3]) + ':' + ('{0:X8}' -f $m[2]) + ' CRCBAP=' + ('{0:X8}' -f $m[5]) + ':' + ('{0:X8}' -f $m[4]) + ' CRDB=' + ('{0:X8}' -f $m[7]) + ':' + ('{0:X8}' -f $m[6])
        $ea = [uint64]$m[2] + [uint64]$m[3] * 4294967296
        if ((($ea -ge (A '80000000')) -and ($ea -lt (A 'D0000000'))) -or (($ea -ge (A 'E0000000')) -and ($ea -lt (A '100000000'))) -or (($ea -ge (A '880000000')) -and ($ea -lt (A 'B00000000')))) {
            $ec = Rm9Read $ea 12
            $x2 += ' | EV0 ertype=' + ('{0:X8}' -f $ec[1]) + ' msivec=' + ('{0:X8}' -f $ec[2]) + ' rbase=' + ('{0:X8}' -f $ec[4]) + ':' + ('{0:X8}' -f $ec[3]) + ' rlen=' + ('{0:X8}' -f $ec[5]) + ' rp=' + ('{0:X8}' -f $ec[8]) + ':' + ('{0:X8}' -f $ec[7]) + ' wp=' + ('{0:X8}' -f $ec[10]) + ':' + ('{0:X8}' -f $ec[9])
            $rb = [uint64]$ec[3] + [uint64]$ec[4] * 4294967296
            if ((($rb -ge (A '80000000')) -and ($rb -lt (A 'D0000000'))) -or (($rb -ge (A 'E0000000')) -and ($rb -lt (A '100000000')))) { $x2 += ' ring[0..7]=' + (Hx (Rm9Read $rb 8)) }
        }
        $gr = A '17180000'
        $pb = (Rm9Read ($gr + 0x70) 1)[0] -band (U 'FFFFF000')
        $cfg = ''
        if (([uint64]$pb -ge (A '80000000')) -and ([uint64]$pb -lt (A 'D0000000'))) { $cfg = Hx (Rm9Read ([uint64]$pb) 4) }
        $pbase = [uint64]((Rm9Read ($gr + 0x78) 1)[0] -band (U 'FFFF0000'))
        $pend = ''
        if (($pbase -ge (A '80000000')) -and ($pbase -lt (A 'D0000000'))) { $pend = ('{0:X8}' -f (Rm9Read ($pbase + 0x400) 1)[0]) + '/' + ('{0:X8}' -f (Rm9Read ($pbase + 0x404) 1)[0]) }
        $x2 += ' | MSI data=' + ('{0:X8}' -f (Rm9Read ($ecamB + 0x58) 1)[0]) + ' mask=' + ('{0:X8}' -f (Rm9Read ($ecamB + 0x5C) 1)[0]) + ' pend=' + ('{0:X8}' -f (Rm9Read ($ecamB + 0x60) 1)[0]) + ' | LPIcfg[0..15]=' + $cfg + ' LPIpending0x2000=' + $pend + ' GICR0.CTLR=' + ('{0:X8}' -f (Rm9Read $gr 1)[0]) + ' MSIsink=' + ('{0:X8}' -f (Rm9Read (A 'D7FF9000') 1)[0])
        if ($x2 -ne $script:mhiPrev) { $script:mhiPrev = $x2; L ("  MHI " + $x2) }
    }
}
function RunTo([string]$exe, [string]$args2, [int]$maxMs) {
    try {
        $j = Start-Job -ScriptBlock { param($e, $a) & $e ($a -split ' ') 2>&1 | Out-String -Width 200 } -ArgumentList $exe, $args2
        if (Wait-Job $j -Timeout ([int]($maxMs / 1000))) {
            (Receive-Job $j) -split "`r?`n" | Select-Object -First 90 | ForEach-Object { L ('    ' + $_) }
        } else { L ('  (' + $exe + ' ' + $args2 + ' timed out)'); Stop-Job $j }
        Remove-Job $j -Force -ErrorAction SilentlyContinue
    } catch { L ('  RunTo failed: ' + $_) }
}
function WifiCheck() {
    L 'WifiCheck: what Windows sees of the Wi-Fi adapter'
    try { Get-NetAdapter -IncludeHidden -ErrorAction Stop | ForEach-Object { L ('  NetAdapter ' + $_.Name + ' | ' + $_.InterfaceDescription + ' | ' + $_.Status + ' | ' + $_.MacAddress) } } catch { L ('  Get-NetAdapter: ' + $_) }
    # netsh wlan show networks needs the location capability (Windows 11): allow it on this bring-up image and start the location service
    RunTo 'reg.exe' 'add HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\CapabilityAccessManager\ConsentStore\location /v Value /t REG_SZ /d Allow /f' 8000
    RunTo 'reg.exe' 'add HKLM\SYSTEM\CurrentControlSet\Services\lfsvc\Service\Configuration /v Status /t REG_DWORD /d 1 /f' 8000
    RunTo 'sc.exe' 'start lfsvc' 15000
    RunTo 'sc.exe' 'query wlansvc' 8000
    RunTo 'sc.exe' 'start wlansvc' 15000
    Start-Sleep 3
    RunTo 'netsh.exe' 'wlan show interfaces' 15000
    RunTo 'netsh.exe' 'wlan show networks mode=bssid' 20000
}
function WifiConnect() {
    # connection test against the user's experimental AP (SSID <LAB_SSID>, WPA2-PSK; the user gave the passphrase for this lab network)
    # S:\rm9\fakessid.flag: ask for an SSID that does not exist (<LAB_SSID>-none) - the driver scans but never authenticates/associates; tells whether the stop after the connect request needs a real association
    $ssid = $(if (Test-Path S:\rm9\fakessid.flag) { '<LAB_SSID>-none' } else { '<LAB_SSID>' })
    L ('WifiConnect: ' + $ssid)
    try {
        $x = '<?xml version="1.0"?><WLANProfile xmlns="http://www.microsoft.com/networking/WLAN/profile/v1"><name><LAB_SSID></name><SSIDConfig><SSID><name><LAB_SSID></name></SSID></SSIDConfig><connectionType>ESS</connectionType><connectionMode>auto</connectionMode><MSM><security><authEncryption><authentication>WPA2PSK</authentication><encryption>AES</encryption><useOneX>false</useOneX></authEncryption><sharedKey><keyType>passPhrase</keyType><protected>false</protected><keyMaterial><PASSPHRASE></keyMaterial></sharedKey></security></MSM></WLANProfile>'
        $x = $x -replace '<LAB_SSID>', $ssid
        Set-Content -Path C:\rm9\a55.xml -Value $x -Encoding ascii
        RunTo 'netsh.exe' 'wlan add profile filename=C:\rm9\a55.xml user=all' 15000
        Remove-Item C:\rm9\a55.xml -Force -ErrorAction SilentlyContinue
        # S:\rm9\staticip.flag: fixed address so Windows sends no DHCP request (isolates whether the first data frames are what kills Windows after the association)
        if (Test-Path S:\rm9\staticip.flag) { L '  static IP mode (no DHCP)'; RunTo 'netsh.exe' 'interface ip set address name=Wi-Fi static 10.99.0.2 255.255.255.0' 15000 }
        RunTo 'netsh.exe' ('wlan connect name=' + $ssid + ' interface=Wi-Fi') 20000
        # heartbeat every second: if Windows freezes after the association (first data frames = DHCP), the last heartbeat time shows when
        $wprev = ''
        $sm = A '15000000'; $cbb = A '15080000'; $dbiW = A '60000000'
        $watchN = $(if ($script:prod) { 200 } else { 600 })
        for ($i = 0; $i -lt $watchN; $i++) {
            if (($i % 10) -eq 0) { L ('  hb ' + ($i / 10)) }
            # fast hardware watch (every 100 ms): SMMU global fault, our context bank (70) fault, root port AER uncorrectable / correctable status; logged when they change
            try {
                $w = 'sGFSR=' + ('{0:X8}' -f (Rm9Read ($sm + 0x48) 1)[0]) + ' CB70.FSR=' + ('{0:X8}' -f (Rm9Read ($cbb + 0x1000 * 70 + 0x58) 1)[0]) + ' AERuc=' + ('{0:X8}' -f (Rm9Read ($dbiW + 0x104) 1)[0]) + ' AERce=' + ('{0:X8}' -f (Rm9Read ($dbiW + 0x110) 1)[0])
                if ($w -ne $wprev) { $wprev = $w; L ('  hw ' + $w) }
            } catch { }
            Start-Sleep -Milliseconds 100
            if (($i % 100) -eq 99) { RunTo 'netsh.exe' 'wlan show interfaces' 15000 }
        }
        RunTo 'ipconfig.exe' '/all' 15000
        RunTo 'ping.exe' '-n 3 -w 2000 8.8.8.8' 15000
        if (Test-Path S:\rm9\disctest.flag) { DiscTest $ssid }
        if (Test-Path S:\rm9\aptest.flag) { ApTest }
        if (Test-Path S:\rm9\soak.flag) { SoakTest }
    } catch { L ('WifiConnect failed: ' + $_) }
}
function SoakTest() {
    # S:\rm9\soak.flag: persistence and speed.  24 minutes after the connection works: every 30 s a ping to the gateway (192.168.x.x) and to 8.8.8.8, every 10 s the hottest TSENS (dbgcap IOCTL), every 5 minutes a 20 MB download over HTTP (Mbit/s).
    # the flag file may hold the number of 30 s rounds (default 48 = 24 min)
    $rounds = 48
    try { $r0 = [int](Get-Content S:\rm9\soak.flag -TotalCount 1); if ($r0 -gt 1) { $rounds = $r0 } } catch { }
    L ('SoakTest: start (' + $rounds + ' rounds of 30 s, poll ' + $script:pollMs + ' ms)')
    $code = [Convert]::ToUInt32('8F002820', 16)
    for ($i = 0; $i -lt $rounds; $i++) {
        $t0 = Get-Date
        try {
            $hot = 'n/a'
            if ([DbgCap]::Open()) { $buf = New-Object byte[] 32; $ret = 0; if ([DbgCap]::DeviceIoControl([DbgCap]::H, $code, $buf, 4, $buf, 32, [ref]$ret, [IntPtr]::Zero)) { $hot = ([BitConverter]::ToInt32($buf, 4) / 10.0) } }
            L ('  soak ' + $i + ' hottest=' + $hot + ' C')
            try { $ir = DbgIrq 2 0 0 0; L ('  soak irq: poll DPC kicks ' + $ir[32] + ' event wakes ' + $ir[69]) } catch { }
        } catch { L ('  soak temp failed: ' + $_.Exception.Message) }
        RunTo 'ping.exe' '-n 2 -w 1500 192.168.x.x' 8000
        RunTo 'ping.exe' '-n 2 -w 1500 8.8.8.8' 8000
        if (($i % 5) -eq 0) {
            try {
                $sw = [Diagnostics.Stopwatch]::StartNew(); $wc = New-Object Net.WebClient
                $b = $wc.DownloadData('http://speed.cloudflare.com/__down?bytes=20000000'); $sw.Stop()
                L ('  download ' + $b.Length + ' bytes in ' + [Math]::Round($sw.Elapsed.TotalSeconds, 1) + ' s = ' + [Math]::Round($b.Length * 8 / 1e6 / $sw.Elapsed.TotalSeconds, 1) + ' Mbit/s')
            } catch { L ('  download failed: ' + $_.Exception.Message) }
        }
        $left = 30 - ((Get-Date) - $t0).TotalSeconds
        if ($left -gt 0) { Start-Sleep -Milliseconds ([int]($left * 1000)) }
    }
    L 'SoakTest: done'
}
function ApTest() {
    # S:\rm9\aptest.flag: the user switches the access point (<LAB_SSID>) off while this window is open (6 minutes), waits 30 s or more, and switches it on again.  1 s heartbeat, every 10 s the adapter state and one ping to the gateway.
    L 'ApTest: WINDOW OPEN - switch the AP off when the Wi-Fi icon shows connected, wait 30 s or more, then switch it on again'
    for ($i = 0; $i -lt 360; $i++) {
        Start-Sleep 1
        L ('  ap hb ' + $i)
        if (($i % 10) -eq 9) {
            RunTo 'netsh.exe' 'wlan show interfaces' 15000
            RunTo 'ping.exe' '-n 1 -w 1500 192.168.x.x' 8000
        }
    }
    L 'ApTest: window closed'
}
function DiscTest([string]$ssid) {
    # S:\rm9\disctest.flag: after the connection works, disconnect (netsh), watch Windows for 30 s (1 s heartbeat), reconnect, watch 20 s, ping.  Before DpPoll, the disconnect path (vdev stop, TX flush) froze Windows.
    L 'DiscTest: netsh wlan disconnect'
    RunTo 'netsh.exe' 'wlan disconnect interface=Wi-Fi' 15000
    for ($i = 0; $i -lt 30; $i++) { Start-Sleep 1; L ('  disc hb ' + $i) }
    RunTo 'netsh.exe' 'wlan show interfaces' 15000
    L 'DiscTest: reconnect (WlanConnect API; netsh wlan connect is refused without the location permission)'
    try {
        Add-Type -TypeDefinition @'
using System; using System.Runtime.InteropServices;
public static class WlanApi {
  [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)] public struct CONNPARAMS { public int mode; public string profile; public IntPtr ssid; public IntPtr bssids; public int bssType; public uint flags; }
  [DllImport("wlanapi.dll")] static extern uint WlanOpenHandle(uint ver, IntPtr res, out uint neg, out IntPtr h);
  [DllImport("wlanapi.dll")] static extern uint WlanCloseHandle(IntPtr h, IntPtr res);
  [DllImport("wlanapi.dll", CharSet = CharSet.Unicode)] static extern uint WlanConnect(IntPtr h, ref Guid iface, ref CONNPARAMS p, IntPtr res);
  public static uint Connect(Guid iface, string profile) {
    uint neg; IntPtr h; uint r = WlanOpenHandle(2, IntPtr.Zero, out neg, out h);
    if (r != 0) return r;
    CONNPARAMS p = new CONNPARAMS(); p.mode = 0; p.profile = profile; p.ssid = IntPtr.Zero; p.bssids = IntPtr.Zero; p.bssType = 3; p.flags = 0;
    r = WlanConnect(h, ref iface, ref p, IntPtr.Zero);
    WlanCloseHandle(h, IntPtr.Zero);
    return r;
  }
}
'@
        $g = [Guid](Get-NetAdapter -Name 'Wi-Fi' -ErrorAction Stop).InterfaceGuid
        L ('  WlanConnect(' + $g + ', ' + $ssid + ') = ' + [WlanApi]::Connect($g, $ssid))
    } catch { L ('  WlanConnect failed: ' + $_) }
    for ($i = 0; $i -lt 20; $i++) { Start-Sleep 1; L ('  recon hb ' + $i) }
    RunTo 'ipconfig.exe' '/all' 15000
    RunTo 'ping.exe' '-n 3 -w 2000 8.8.8.8' 15000
    L 'DiscTest: done'
}
function CrumbDump([string]$tag) {
    # the breadcrumb text dbgcap.sys keeps in DRAM (0xD7E00000: sig,start,size then ASCII): first and last parts
    try {
        $h = Rm9Read (A 'D7E00000') 3
        $n = [int]($h[2] -band 0xFFFFF)
        L ('crumb ' + $tag + ': size ' + $n)
        foreach ($seg in @(@(0, 768), @([Math]::Max(0, $n - 1536), 384))) {
            $off = $seg[0]; $cnt = $seg[1]
            if ($off + 4 * $cnt -gt 0xF0000) { continue }
            $w = Rm9Read ((A 'D7E00000') + 12 + [uint64]$off) $cnt
            $sb = New-Object System.Text.StringBuilder
            foreach ($x in $w) { for ($b = 0; $b -lt 4; $b++) { $c = [int](($x -shr (8 * $b)) -band 0xFF); if ($c -eq 10) { [void]$sb.Append('|') } elseif ($c -ge 32 -and $c -lt 127) { [void]$sb.Append([char]$c) } else { [void]$sb.Append('.') } } }
            L ('  crumb[' + $off + ']: ' + $sb.ToString())
        }
    } catch { L ('crumb dump failed: ' + $_) }
}
function Show($pat, $tag) {
    Get-PnpDevice | Where-Object { $_.InstanceId -like $pat } | ForEach-Object { L ("$tag " + $_.InstanceId + ' status=' + $_.Status + ' problem=' + $_.Problem + ' present=' + $_.Present) }
}
Remove-Item C:\rm9\rp.etl -ErrorAction SilentlyContinue
logman create trace rm9rp -ets -p 'Microsoft-Windows-Kernel-PnP' 0xFFFFFFFFFFFFFFFF 0xFF -o C:\rm9\rp.etl 2>&1 | Out-Null
logman update trace rm9rp -ets -p 'Microsoft-Windows-PCI' 0xFFFFFFFFFFFFFFFF 0xFF 2>&1 | Out-Null
Show 'PCI*VEN_17CB*' 'before'
$rp = (Get-PnpDevice | Where-Object { $_.InstanceId -like 'PCI*VEN_17CB&DEV_0113*' } | Select-Object -First 1).InstanceId
if (-not $rp) { L 'no root port device'; return }
$dbi = A '60000000'
L ('RP cfg [40..5F] before: ' + (Hx (Rm9Read ($dbi + 0x40) 8)))
$c = (Rm9Read ($dbi + 0x8BC) 1)[0]
Rm9Write ($dbi + 0x8BC) ($c -bor 1)
if (Test-Path S:\rm9\rpintx.flag) {
    # S:\rm9\rpintx.flag: give the root port a LEGACY interrupt instead of its MSI: Interrupt Pin (config 0x3D) = 1 (INTA) -> the DSDT's _PRT (device 0 -> GSI 181) gives pci.sys an interrupt resource and the
    # MSI capability stays hidden, so Windows never maps the root port's MSI in the ITS (DeviceID 0x1301 is not a physical device of the VM: its MAPD V=0 is ERROR_UNIMPLEMENTED in Gunyah and freezes the hypervisor)
    $ip = (Rm9Read ($dbi + 0x3C) 1)[0]
    Rm9Write ($dbi + 0x3C) (($ip -band (U 'FFFF00FF')) -bor 0x100)
    L ('RP INTx mode: config 0x3C was ' + ('{0:X8}' -f $ip) + ' now ' + ('{0:X8}' -f (Rm9Read ($dbi + 0x3C) 1)[0]) + ' (MSI capability stays hidden)')
} else {
    $pm = (Rm9Read ($dbi + 0x40) 1)[0]
    Rm9Write ($dbi + 0x40) (($pm -band (U 'FFFF00FF')) -bor 0x5000)
}
Rm9Write ($dbi + 0x8BC) ($c -band (U 'FFFFFFFE'))
L ('RP cfg [40..5F] after:  ' + (Hx (Rm9Read ($dbi + 0x40) 8)) + '  (MISC_CONTROL_1 was ' + ('{0:X8}' -f $c) + ' now ' + ('{0:X8}' -f (Rm9Read ($dbi + 0x8BC) 1)[0]) + ')')
L 'restarting PCI0 (rebuilds the bus: the root port PDO is created again and reads its capabilities again)'
$p1 = Start-Process pnputil -ArgumentList "/restart-device `"ACPI\PNP0A08\0`"" -PassThru -WindowStyle Hidden
Pump 20 'rp'
Show 'PCI*VEN_17CB*' 'after-rp'
PrivateLpiTest 'after the root port'
$ep = Get-PnpDevice | Where-Object { $_.InstanceId -like 'PCI*VEN_17CB&DEV_1107*' -and $_.Present } | Select-Object -First 1
if ($ep) {
    L "endpoint present: $($ep.InstanceId) status=$($ep.Status) problem=$($ep.Problem)"
    # the driver only prints its own log when its debug parameters are set in the net-class software key (MPGlobalDebugLevel / MPGlobalDebugComponents / GlobalDebugLogOutput)
    try {
        $keys = @()
        foreach ($k in (Get-ChildItem 'HKLM:\SYSTEM\CurrentControlSet\Enum\PCI' -ErrorAction SilentlyContinue | Where-Object { $_.PSChildName -match 'VEN_17CB&DEV_1107' })) {
            foreach ($i in (Get-ChildItem $k.PSPath -ErrorAction SilentlyContinue)) { $d = (Get-ItemProperty $i.PSPath -ErrorAction SilentlyContinue).Driver; if ($d) { $keys += ('HKLM:\SYSTEM\CurrentControlSet\Control\Class\' + $d) } }
        }
        foreach ($kp in $keys) {
            foreach ($nv in @(@('MPGlobalDebugLevel', 9), @('MPGlobalDebugComponents', -1), @('GlobalDebugLogOutput', 255), @('logLevel', 9), @('powerDebug', 1), @('RecoveryPolicy', 0))) { Set-ItemProperty -Path $kp -Name $nv[0] -Value ([int]$nv[1]) -Type DWord -ErrorAction SilentlyContinue }
            L ('  debug parameters set in ' + $kp)
        }
        if (-not $keys) { L '  no driver software key found for the debug parameters' }
    } catch { L ('  debug parameters failed: ' + $_) }
    # the driver's own log goes to two ETW providers (EtwRegister GUIDs found in the binary): record both into the ESP (flush every second)
    if (-not $script:prod) { try {
        Remove-Item S:\rm9\qcw.etl -ErrorAction SilentlyContinue
        $gl = @('{bb6f5b93-635c-47be-816f-e895e77064a8} 0xFFFFFFFFFFFFFFFF 0xFF', '{5412704e-b2e1-4624-8ffd-55777b8f7373} 0xFFFFFFFFFFFFFFFF 0xFF')
        Set-Content -Path C:\rm9\qcw.guids -Value $gl -Encoding ascii
        $lo = (logman.exe create trace qcw -pf C:\rm9\qcw.guids -o S:\rm9\qcw.etl -ets -f bincirc -max 24 -ft 1 -bs 4 -nb 16 128 2>&1) -join ' | '
        L ('  logman: ' + $lo)
    } catch { L ('  logman failed: ' + $_) } }
    sc.exe config qcwlan start= demand | Out-Null
    L 'qcwlan enabled, restarting the endpoint (async)'
    $p2 = Start-Process pnputil -ArgumentList "/restart-device `"$($ep.InstanceId)`"" -PassThru -WindowStyle Hidden
    Pump 60 'ep'
    WifiCheck
    WifiConnect
    if (Test-Path S:\rm9\mbitest.flag) { MbiTest }
    if (Test-Path S:\rm9\inttest.flag) { IntTest }
    if (Test-Path S:\rm9\iar0.flag) { IarCpu0 }
    if (Test-Path S:\rm9\spin0.flag) { SpinTest }
    if (Test-Path S:\rm9\hppir0.flag) { HppirCpu0 }
    if (Test-Path S:\rm9\mbiring.flag) { MbiRing }
    if (Test-Path S:\rm9\spiprobe.flag) { SpiProbe }
    if (Test-Path S:\rm9\irqtest.flag) { IrqTest }
    if (Test-Path S:\rm9\irqdrv.flag) { IrqDrvTest }
    if (Test-Path S:\rm9\irqkick.flag) { IrqKickTest }
    if (Test-Path S:\rm9\kickspeed.flag) { KickSpeedTest }
    Pump 60 'ep'
    Show 'PCI*VEN_17CB*' 'after-ep'
    $sm = A '15000000'; $cbb = A '15080000'
    L ('SMMU sGFSR=' + ('{0:X8}' -f (Rm9Read ($sm + 0x48) 1)[0]) + ' sGFAR=' + (Hx (Rm9Read ($sm + 0x40) 2)) + ' sGFSYNR0..2=' + (Hx (Rm9Read ($sm + 0x50) 3)) + ' sCR0=' + ('{0:X8}' -f (Rm9Read $sm 1)[0]))
    $ncb = (Rm9Read ($sm + 0x24) 1)[0] -band 0xFF
    for ($c = 0; $c -lt $ncb; $c++) {
        $b = $cbb + 0x1000 * $c
        $fsr = (Rm9Read ($b + 0x58) 1)[0]; $sc = (Rm9Read $b 1)[0]
        if ((($sc -band 1) -ne 0) -and ((Rm9Read ($sm + 0x1000 + 4 * $c) 1)[0] -eq 0x10000)) {
            $t0 = (Rm9Read ($b + 0x20) 1)[0]; $t1 = (Rm9Read ($b + 0x24) 1)[0]
            L ('  CB' + $c + ' ours: TTBR0=' + ('{0:X8}' -f $t1) + ':' + ('{0:X8}' -f $t0) + ' TCR=' + ('{0:X8}' -f (Rm9Read ($b + 0x30) 1)[0]) + ' TCR2=' + ('{0:X8}' -f (Rm9Read ($b + 0x10) 1)[0]) + ' MAIR0=' + ('{0:X8}' -f (Rm9Read ($b + 0x38) 1)[0]) + ' CBA2R=' + ('{0:X8}' -f (Rm9Read ($sm + 0x1800 + 4 * $c) 1)[0]) + ' table=' + (Hx (Rm9Read ([uint64]$t0 + [uint64]$t1 * 4294967296) 8)))
        }
        if (($fsr -ne 0) -or (($sc -band 1) -ne 0)) { L ('  CB' + $c + ' SCTLR=' + ('{0:X8}' -f $sc) + ' FSR=' + ('{0:X8}' -f $fsr) + ' FAR=' + (Hx (Rm9Read ($b + 0x60) 2)) + ' FSYNR0=' + ('{0:X8}' -f (Rm9Read ($b + 0x68) 1)[0]) + ' CBAR=' + ('{0:X8}' -f (Rm9Read ($sm + 0x1000 + 4 * $c) 1)[0])) }
    }
    sc.exe config qcwlan start= disabled | Out-Null
} else { L 'endpoint not present' }
logman stop rm9rp -ets 2>&1 | Out-Null
try { tracerpt C:\rm9\rp.etl -of CSV -o S:\rm9\rp_trace.csv -y 2>&1 | Out-Null } catch {}
Select-String -Path S:\rm9\rp_trace.csv -Pattern 'Microsoft-Windows-PCI|Microsoft-Windows-Kernel-PnP' | Where-Object { $_.Line -notmatch ', (501|502|503|500)," ' } | ForEach-Object { ($_.Line -replace '\s+', ' ') } | Out-File -Encoding ascii S:\rm9\rp_small.csv
Remove-Item S:\rm9\rp_trace.csv -ErrorAction SilentlyContinue
L ('RP cfg after: ' + (Hx (Rm9Read $dbi 16)))
L ('EP cfg: ' + (Hx (Rm9Read (A '60100000') 16)))
L ('crumb header @D7E00000 at the end: ' + (Hx (Rm9Read (A 'D7E00000') 8)))
CrumbDump 'end'
L 'done'
if ($script:prod) {
    # production: the polling / kick threads live in dbgcap.sys and the Wi-Fi profile reconnects by itself, so nothing here has to keep running.  Nodes stay (= nocleanup 'keep'); no restart.
    L 'prod: Wi-Fi stays up (no cleanup, no restart)'
    return
}

# in-boot cleanup + immediate restart (replaces the separate cleanup boot and the 10 minute safety timer): forget the RP / WCN7850 device nodes Windows would otherwise remember, then restart
# nocleanup.flag: absent = remove every PCI*VEN_17CB* node; content 'keep' = remove none, 'keeprp' = remove only the endpoint nodes (DEV_1107), 'keepep' = remove only the root port nodes (DEV_0113)
$mode = 'all'
if (Test-Path S:\rm9\nocleanup.flag) { $mode = ((Get-Content S:\rm9\nocleanup.flag -ErrorAction SilentlyContinue) -join '').Trim(); if (-not $mode) { $mode = 'keep' } }
L ('cleanup mode: ' + $mode)
# stop the MHI poll work items before any device node goes away (the driver functions they call vanish with the device -> BSOD/freeze at remove-device)
function StopPoll() { if ($script:dbgOn -and $script:qcBase) { try { $pp = DbgPoll $script:qcBase 0; L ('poll stopped: ' + (Hx $pp)) } catch { L ('poll stop failed: ' + $_) } } }
if ($mode -ne 'disableall') { StopPoll }   # 'disableall' keeps polling during the disable (the driver's MHI power-down needs the ring handlers) and stops it afterwards
if ($mode -eq 'disableall') {
    # experiment: disable the endpoint (qcwlan) first so the driver shuts down cleanly, then remove every node like mode 'all'
    $mode = 'all'
    # disconnect, then stop only the data-path polling (hif_deregister_exec_group frees the groups the poll would call); MHI/CE polling continues for the MHI power-down
    try { RunTo 'netsh.exe' 'wlan disconnect interface=Wi-Fi' 15000; Start-Sleep 3 } catch { L ('disconnect failed: ' + $_) }
    try { $pd = DbgPoll $script:qcBase 4294967294; L ('data-path polling stopped: ' + (Hx $pd)) } catch { L ('dp poll stop failed: ' + $_) }
    try {
        foreach ($id in @(Get-PnpDevice | Where-Object { $_.InstanceId -like 'PCI*VEN_17CB&DEV_1107*' } | ForEach-Object { $_.InstanceId })) {
            L ('cleanup: disable-device ' + $id); (pnputil /disable-device "$id" 2>&1) -join ' ' | ForEach-Object { L ('  ' + $_) }
            Start-Sleep 3
            L ('cleanup: after disable ' + $id + ' ' + ((Get-PnpDevice -InstanceId $id -ErrorAction SilentlyContinue | ForEach-Object { $_.Status }) -join ','))
        }
    } catch { L ('disable failed: ' + $_) }
    StopPoll
}
if ($mode -ne 'keep') {
    try {
        $ids = @(Get-PnpDevice | Where-Object { $_.InstanceId -like 'PCI*VEN_17CB*' } | ForEach-Object { $_.InstanceId } | Sort-Object { if ($_ -like '*DEV_1107*') { 0 } else { 1 } })   # child (endpoint) before parent (root port)
        foreach ($id in $ids) {
            if ($id -like '*DEV_0113*') {
                # quiesce the WCN7850 before the root port goes away: its firmware keeps DMAing into memory the driver freed, the root port stop closes the bus and (suspected) freezes the CPU complex.
                # Android's power-off state (MuChain.c trace 2026-10-21): WLAN_EN (TLMM gpio16) low, PERST (gpio94) left high.  gpio N: TLMM 0x0F100000 + 0x1000 * N, +4 = IN_OUT (bit1 = output value).
                try {
                    $tl = A '0F100000'
                    L ('quiesce: gpio16 (WLAN_EN) io=' + ('{0:X}' -f (Rm9Read ($tl + 0x1000 * 16 + 4) 1)[0]) + ' gpio94 (PERST) io=' + ('{0:X}' -f (Rm9Read ($tl + 0x1000 * 94 + 4) 1)[0]))
                    Rm9Write ($tl + 0x1000 * 16 + 4) 0
                    Start-Sleep -Milliseconds 300
                    L ('quiesce: WLAN_EN low; gpio16 io=' + ('{0:X}' -f (Rm9Read ($tl + 0x1000 * 16 + 4) 1)[0]))
                } catch { L ('quiesce failed: ' + $_) }
                Start-Sleep 3
            }
            if ($mode -eq 'keeprp' -and $id -like '*DEV_0113*') { L ('cleanup: keeping ' + $id); continue }
            if ($mode -eq 'keepep' -and $id -like '*DEV_1107*') { L ('cleanup: keeping ' + $id); continue }
            if ($id -like '*DEV_0113*' -and (Test-Path S:\rm9\disablerp.flag)) {
                # the root port node is never stopped / removed (every PnP stop of it freezes Windows, and a remembered one makes the next boot hang): mark it disabled in the registry instead (ConfigFlags = CONFIGFLAG_DISABLED);
                # a disabled node is not started at boot, so nothing ever stops it.  The endpoint is enumerated by the PCI0 bus driver whether the (always FAILED_START) root port FDO runs or not.
                L ('cleanup: registry-disable ' + $id)
                (reg add ('HKLM\SYSTEM\CurrentControlSet\Enum\' + $id) /v ConfigFlags /t REG_DWORD /d 1 /f 2>&1) -join ' ' | ForEach-Object { L ('  ' + $_) }
                continue
            }
            L ('cleanup: remove-device ' + $id); (pnputil /remove-device "$id" 2>&1) -join ' ' | ForEach-Object { L ('  ' + $_) }
            if ($id -like '*DEV_1107*') {
                # remove-device is asynchronous: power the chip down only after the endpoint is really gone (2026-10-29 14:30: WLAN_EN low during the removal froze Windows)
                for ($w = 0; $w -lt 30; $w++) { if (-not (Get-PnpDevice -InstanceId $id -ErrorAction SilentlyContinue)) { break }; Start-Sleep -Milliseconds 500 }
                L ('  endpoint gone after ' + ($w * 0.5) + ' s'); Start-Sleep 3
            }
        }
        Start-Sleep 3
        L ('cleanup: left ' + (@(Get-PnpDevice | Where-Object { $_.InstanceId -like 'PCI*VEN_17CB*' }).Count) + ' devices')
    } catch { L ('cleanup failed: ' + $_) }
}
if (Test-Path S:\rm9\delkeys.flag) {
    # forget the nodes WITHOUT a PnP stop: delete the Enum keys of the root port and the endpoint directly right before the restart (a remembered node makes the next boot stall ~172 s before run.cmd; every PnP stop/removal of the root port freezes Windows)
    foreach ($kn in @('PCI\VEN_17CB&DEV_1107&SUBSYS_110717CB&REV_01', 'PCI\VEN_17CB&DEV_0113&SUBSYS_00000000&REV_00')) {
        L ('cleanup: reg delete Enum\' + $kn)
        (reg delete ('HKLM\SYSTEM\CurrentControlSet\Enum\' + $kn) /f 2>&1) -join ' ' | ForEach-Object { L ('  ' + $_) }
        L ('  exists after: ' + (Test-Path ('HKLM:\SYSTEM\CurrentControlSet\Enum\' + $kn)))
    }
}
L 'back to normal CPU count (numproc removed)'
(bcdedit /deletevalue '{current}' numproc 2>&1) -join ' ' | ForEach-Object { L ('  ' + $_) }
L 'restart'
shutdown /a | Out-Null
shutdown /r /t 3 /f
