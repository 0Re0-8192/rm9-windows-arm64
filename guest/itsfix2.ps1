# itsfix.ps1 - make Windows' MSI setup work on this ITS.  Findings (2026-10-23, itscmd6):  (1) GITS_TYPER ID_bits=7, so MAPD Size must be <= 7; Windows sends Size 9 -> ITS stalls (CREADR bit0).
# (2) the device table is two-level (BASER0 hi 0xF9070000, 8-byte entries): a MAPD needs L1[DeviceID>>9] to point to a level-2 page; with one it is ACCEPTED (Size 1 and 7 tested).
# This script starts the WCN7850 driver (qcwlan Start=4 -> demand, restart the device), watches GITS_CREADR, and when the ITS stalls on a MAPD it rewrites Size to 7, installs a level-2 page if L1 is empty and
# writes GITS_CWRITER with Retry (bit 0) to restart the queue.  Log: S:\rm9\wifi_itsfix2.txt (FAT, survives an unclean stop).  Never read GITS offset 0xC.  Registers are written 32 bits at a time only for CWRITER.
$o = 'S:\rm9\wifi_itsfix2.txt'
$fs = New-Object IO.FileStream($o, [IO.FileMode]::Append, [IO.FileAccess]::Write, [IO.FileShare]::ReadWrite, 4096, [IO.FileOptions]::WriteThrough)
function L($m) { $b = [Text.Encoding]::ASCII.GetBytes("$(Get-Date -Format 'HH:mm:ss.fff') $m`r`n"); $fs.Write($b, 0, $b.Length); $fs.Flush($true) }
function A([string]$h) { [Convert]::ToUInt64($h, 16) }
function U([string]$h) { [Convert]::ToUInt32($h, 16) }
function Hx($a) { ($a | ForEach-Object { '{0:X8}' -f $_ }) -join ' ' }
. C:\rm9\link\rm9io.ps1
if ((Get-Service rm9io -ErrorAction SilentlyContinue).Status -ne 'Running') { Start-Service rm9io -ErrorAction SilentlyContinue; Start-Sleep 1 }
Start-Sleep 70
L 'itsfix2 start'
$dev = Get-PnpDevice -PresentOnly | Where-Object { $_.InstanceId -like 'PCI*VEN_17CB*' } | Select-Object -First 1
if (-not $dev) { L 'no VEN_17CB device'; return }
$id = $dev.InstanceId
L "device $id status=$($dev.Status) problem=$($dev.Problem)"
$its = A '17140000'
function Its32($off) { (Rm9Read ($its + $off) 1)[0] }
$cb = Its32 0x80
$q = [uint64]($cb -band (U 'FFFFF000'))
if ($q -eq 0) { L 'no ITS queue (HAL has not set the ITS up): stopping'; return }
$l1 = [uint64]((Its32 0x100) -band (U 'FFFFF000'))
L ('CBASER ' + ('{0:X8}' -f (Its32 0x84)) + ':' + ('{0:X8}' -f $cb) + ' BASER0 ' + ('{0:X8}' -f (Its32 0x104)) + ':' + ('{0:X8}' -f (Its32 0x100)) + ' L1 @' + ('{0:X}' -f $l1) + ' queue @' + ('{0:X}' -f $q))
$pool = @((A 'D7FF4000'), (A 'D7FF5000'), (A 'D7FF6000'), (A 'D7FF7000')); $poolUsed = 0
$V = U '80000000'
function State() { 'cr=' + ('{0:X8}' -f (Its32 0x90)) + ' cw=' + ('{0:X8}' -f (Its32 0x88)) }
function Fix([uint32]$cr) {
    $off = [uint64]($cr -band (U 'FFFFFFFE'))
    $w = Rm9Read ($q + $off) 8
    L ('STALL at queue+' + ('{0:X}' -f $off) + ': ' + (Hx $w))
    if (($w[0] -band 0xFF) -ne 8) { L 'not a MAPD: not touching'; return $false }
    $devid = $w[1]; $size = $w[2] -band 0x1F
    if ($size -gt 7) {
        Rm9Write ($q + $off + 8) (($w[2] -band (U 'FFFFFFE0')) -bor 7)
        L "  MAPD size $size -> 7"
    }
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
    $w2 = Rm9Read ($q + $off) 8
    L ('  command now: ' + (Hx $w2))
    $cw = Its32 0x88
    Rm9Write ($its + 0x88) ($cw -bor 1)       # GITS_CWRITER.Retry
    Start-Sleep -Milliseconds 30
    L ('  after Retry: ' + (State))
    return $true
}
L ('before ' + (State))
sc.exe config qcwlan start= demand | Out-Null
L 'qcwlan enabled, restarting the device (async)'
$p = Start-Process pnputil -ArgumentList "/restart-device `"$id`"" -PassThru -WindowStyle Hidden
$prev = ''; $n = 0; $handled = @{}; $t0 = Get-Date
for ($i = 0; ((Get-Date) - $t0).TotalSeconds -lt 150; $i++) {
    $s = State
    if ($s -ne $prev) { L ("s$i $s"); $prev = $s; $n++ }
    $cr = Its32 0x90
    if (($cr -band 1) -and -not $handled.ContainsKey($cr)) { $handled[$cr] = 1; [void](Fix $cr) }
    if ($i -eq 3000) { sc.exe config qcwlan start= disabled | Out-Null; L 'qcwlan back to disabled' }
    if ($n -gt 400) { break }
}

L '--- after the start attempt'
$cwF = Its32 0x88
L ('ITS final ' + (State) + ' queue commands (opcode, DeviceID/ICID, DW1, DW2):')
for ($off = 0; $off -lt $cwF -and $off -lt 0x1000; $off += 32) { $w = Rm9Read ($q + $off) 8; L ('  +{0:X3}: {1}' -f $off, (Hx $w)) }
$D = 'S:\rm9\wifi_diag2.txt'
function W($m) { "$(Get-Date -Format 'HH:mm:ss') $m" | Out-File -Append -Encoding ascii $D }
$dev2 = Get-PnpDevice -PresentOnly | Where-Object { $_.InstanceId -like 'PCI*VEN_17CB*' } | Select-Object -First 1
if ($dev2) {
    $id2 = $dev2.InstanceId
    W "device $id2 status=$($dev2.Status) problem=$($dev2.Problem)"
    try { Get-PnpDeviceProperty -InstanceId $id2 | Where-Object { $_.KeyName -match 'Problem|DriverProblem|Status|Service|InterruptSupport|InterruptMessage|BusReported|Install' } | ForEach-Object { W ("  prop {0} = {1}" -f $_.KeyName, $_.Data) } } catch { W "prop err: $_" }
    W 'pnputil resources:'; pnputil /enum-devices /instanceid "$id2" /resources 2>&1 | Out-File -Append -Encoding ascii $D
}
foreach ($ch in 'System', 'Microsoft-Windows-Kernel-PnP/Configuration', 'Microsoft-Windows-Kernel-PnP/Device Management') {
    W "events $ch (last 400, filtered)"
    try { Get-WinEvent -LogName $ch -MaxEvents 400 -ErrorAction Stop | Where-Object { $_.Message -match '17CB|1107|qcwlan|FastConnect|WCN|wifi|wlan' -or $_.ProviderName -match 'qcwlan' } | Select-Object -First 15 | ForEach-Object { W ("  {0} id={1} {2}: {3}" -f $_.TimeCreated.ToString('HH:mm:ss'), $_.Id, $_.ProviderName, (($_.Message -replace "`r?`n", ' | ')).Substring(0, [Math]::Min(500, $_.Message.Length))) } } catch { W "events err: $_" }
}
$ecam = A '60100000'
W ('EP config 0x00..0x3F: ' + (Hx (Rm9Read $ecam 16)))
$bar = (Rm9Read ($ecam + 0x10) 1)[0]; $cmd = (Rm9Read ($ecam + 4) 1)[0]
W ('EP cmd/status ' + ('{0:X8}' -f $cmd) + ' BAR0 ' + ('{0:X8}' -f $bar) + ' msi cap (0x50..0x5F): ' + (Hx (Rm9Read ($ecam + 0x50) 4)))
if ((($cmd -band 2) -ne 0) -and (($bar -band (U 'FFFFFFF0')) -ne 0)) { W ('MHI regs @BAR0: ' + (Hx (Rm9Read ([uint64]($bar -band (U 'FFFFFFF0'))) 16))) }
$dv = Get-PnpDevice -PresentOnly | Where-Object { $_.InstanceId -like 'PCI*VEN_17CB*' } | Select-Object -First 1
L ("end: device status=$($dv.Status) problem=$($dv.Problem) pnputil exited=$($p.HasExited) changes=$n " + (State))
sc.exe config qcwlan start= disabled | Out-Null
L 'done'
