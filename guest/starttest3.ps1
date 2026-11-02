# starttest.ps1 - start the WCN7850 driver on purpose and record what the hardware does until the machine stops (CLOCK_WATCHDOG_TIMEOUT).  Output C:\rm9\wifi_start3.txt (write-through: every line is on disk before the next step).
# qcwlan is Start=4 (disabled) at boot (esp_run_*.cmd); this script enables it, restarts the device asynchronously and puts Start=4 back 3 s later, so a crash does not repeat at the next boot.
$o = 'C:\rm9\wifi_start3.txt'
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
function Sample($tag) {
    L ("$tag cr=" + (Hx (Rm9Read (A '17140090') 1)) + " cw=" + (Hx (Rm9Read (A '17140088') 1)) + " gits=" + (Hx (Rm9Read (A '17140000') 1)) + " gicr=" + (Hx (Rm9Read (A '17180000') 1)) + " cmd=" + (Hx (Rm9Read (A '60100004') 1)) + " bar=" + (Hx (Rm9Read (A '60100010') 1)) + " msi=" + (Hx (Rm9Read (A '60100050') 3)) + " lnk=" + (Hx (Rm9Read (A '60100080') 1)) + " parf=" + (Hx (Rm9Read (A '01C001B0') 1)))
}
Sample 'before'
L 'enabling qcwlan, restarting the device (async)'
sc.exe config qcwlan start= demand | Out-Null
$p = Start-Process pnputil -ArgumentList "/restart-device `"$id`"" -PassThru -WindowStyle Hidden
$dumped = $false
for ($i = 0; $i -lt 3000; $i++) {
    Sample ("s$i")
    if (-not $dumped -and (Rm9Read (A '17140090') 1)[0] -ne 0) {
        $dumped = $true
        L ('ITS CTLR/IIDR/TYPER ' + (Hx (Rm9Read (A '17140000') 4)) + ' STATUSR ' + (Hx (Rm9Read (A '17140040') 1)))
        $cb = Rm9Read (A '17140080') 4
        L ('ITS CBASER lo/hi ' + (Hx $cb[0..1]) + ' CWRITER ' + (Hx $cb[2..3]))
        L ('ITS CREADR ' + (Hx (Rm9Read (A '17140090') 2)))
        L ('ITS BASER0..7 ' + (Hx (Rm9Read (A '17140100') 16)))
        L ('GICR CTLR/IIDR/TYPER ' + (Hx (Rm9Read (A '17180000') 4)) + ' PROP ' + (Hx (Rm9Read (A '17180070') 2)) + ' PEND ' + (Hx (Rm9Read (A '17180078') 2)))
        $q = [uint64]($cb[0] -band 0xFFFFF000) + ([uint64]$cb[1] -shl 32)
        L ('queue phys ' + ('{0:X}' -f $q) + ' first 16 dwords: ' + (Hx (Rm9Read $q 16)))
    }
    if ($i -eq 40) { sc.exe config qcwlan start= disabled | Out-Null; L 'qcwlan back to disabled' }
}
L ('pnputil exited=' + $p.HasExited)
$d = Get-PnpDevice -PresentOnly | Where-Object { $_.InstanceId -like 'PCI*VEN_17CB*' } | Select-Object -First 1
L "after: status=$($d.Status) problem=$($d.Problem)"
L 'done'
