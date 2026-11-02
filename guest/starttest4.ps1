# starttest.ps1 - start the WCN7850 driver on purpose and record what the hardware does until the machine stops (CLOCK_WATCHDOG_TIMEOUT).  Output C:\rm9\wifi_start4.txt (write-through: every line is on disk before the next step).
# qcwlan is Start=4 (disabled) at boot (esp_run_*.cmd); this script enables it, restarts the device asynchronously and puts Start=4 back 3 s later, so a crash does not repeat at the next boot.
$o = 'C:\rm9\wifi_start4.txt'
$fs = New-Object IO.FileStream($o, [IO.FileMode]::Append, [IO.FileAccess]::Write, [IO.FileShare]::ReadWrite, 4096, [IO.FileOptions]::WriteThrough)
function L($m) { $b = [Text.Encoding]::ASCII.GetBytes("$(Get-Date -Format 'HH:mm:ss.fff') $m`r`n"); $fs.Write($b, 0, $b.Length); $fs.Flush($true) }
function A([string]$h) { [Convert]::ToUInt64($h, 16) }
function Hx($a) { ($a | ForEach-Object { '{0:X8}' -f $_ }) -join ' ' }
. C:\rm9\link\rm9io.ps1
if ((Get-Service rm9io -ErrorAction SilentlyContinue).Status -ne 'Running') { Start-Service rm9io -ErrorAction SilentlyContinue; Start-Sleep 1 }
Start-Sleep 70
$dev = Get-PnpDevice -PresentOnly | Where-Object { $_.InstanceId -like 'PCI*VEN_17CB*' } | Select-Object -First 1
if (-not $dev) { L 'no VEN_17CB device'; return }
$id = $dev.InstanceId
L "device $id status=$($dev.Status) problem=$($dev.Problem)"
L ('qcwlan Start=' + (Get-ItemProperty HKLM:\SYSTEM\CurrentControlSet\Services\qcwlan).Start)
$its = A '17140000'
function Its32($off) { (Rm9Read ($its + $off) 1)[0] }
$cbase = (Its32 0x80) -band 0xFFFFF000
L ('CBASER lo ' + ('{0:X8}' -f (Its32 0x80)) + ' queue phys ' + ('{0:X8}' -f $cbase))
if ($cbase -eq 0) { L 'no ITS queue address (HAL has not set the ITS up): stopping'; return }
$q = [uint64]$cbase
$b0 = [uint64]((Its32 0x100) -band 0xFFFFF000); $b1 = [uint64]((Its32 0x108) -band 0xFFFFF000)
L ('BASER0 lo ' + ('{0:X8}' -f (Its32 0x100)) + ' BASER1 lo ' + ('{0:X8}' -f (Its32 0x108)))
function State() { ('cr=' + ('{0:X8}' -f (Its32 0x90)) + ' cw=' + ('{0:X8}' -f (Its32 0x88)) + ' ctlr=' + ('{0:X8}' -f (Its32 0)) + ' q=' + (Hx (Rm9Read $q 8))) }
L ('before ' + (State))
L 'enabling qcwlan, restarting the device (async)'
sc.exe config qcwlan start= demand | Out-Null
$p = Start-Process pnputil -ArgumentList "/restart-device `"$id`"" -PassThru -WindowStyle Hidden
$prev = ''; $n = 0; $dumped = $false
for ($i = 0; $i -lt 200000; $i++) {
    $s = State
    if ($s -ne $prev) {
        L ("s$i $s"); $prev = $s; $n++
        if (-not $dumped -and (Its32 0x88) -ne 0) {
            $dumped = $true
            if ($b0) { L ('devtable L1 @' + ('{0:X}' -f $b0) + ': ' + (Hx (Rm9Read $b0 8))) }
            if ($b1) { L ('collection table @' + ('{0:X}' -f $b1) + ': ' + (Hx (Rm9Read $b1 8))) }
            L ('queue 2nd..4th command: ' + (Hx (Rm9Read ($q + 32) 24)))
        }
    }
    if ($i -eq 3000) { sc.exe config qcwlan start= disabled | Out-Null; L 'qcwlan back to disabled' }
}
L ('pnputil exited=' + $p.HasExited + ' changes=' + $n)
L 'done'
