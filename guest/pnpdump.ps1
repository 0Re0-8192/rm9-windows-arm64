# pnpdump.ps1 - after boot: what does Windows make of the PCIe0 host bridge and the WCN7850 behind it?  Output C:\rm9\pnp_pci.txt (read from Android afterwards).
$o = 'C:\rm9\pnp_pci.txt'
function W($m) { $m | Out-File -Append -Encoding ascii $o }
function Dump($tag) {
    W "==== $tag $(Get-Date -Format 'HH:mm:ss')"
    try {
        Get-PnpDevice -PresentOnly | Where-Object { $_.InstanceId -like 'PCI*' -or $_.InstanceId -like 'ACPI\PNP0A0*' -or $_.InstanceId -like 'ACPI\PNP0C02*' -or $_.Status -ne 'OK' } |
            Sort-Object InstanceId | Format-List InstanceId, FriendlyName, Class, Status, Problem | Out-File -Append -Encoding ascii $o
    } catch { W "err: $_" }
    try { Get-CimInstance Win32_PnPEntity | Where-Object { $_.PNPDeviceID -like 'PCI*' } | Format-List Name, PNPDeviceID, ConfigManagerErrorCode, Status | Out-File -Append -Encoding ascii $o } catch { W "err2: $_" }
}
function A([string]$h) { [Convert]::ToUInt64($h, 16) }          # never type a high hex literal: PowerShell makes it a negative Int32
Start-Sleep 100; Dump 'T+100s'
Start-Sleep 100; Dump 'T+200s'
# raw look at the hardware the way MuChain left it: ECAM window (dev 0 = the endpoint), DBI (root port), PARF LTSSM.  Last, because a bad access could stop the machine.
try {
    . C:\rm9\link\rm9io.ps1
    if ((Get-Service rm9io -ErrorAction SilentlyContinue).Status -ne 'Running') { Start-Service rm9io -ErrorAction SilentlyContinue; Start-Sleep 1 }
    $ep  = Rm9Read (A '60100000') 4
    W ('raw ECAM d0f0: ' + (($ep  | ForEach-Object { '{0:X8}' -f $_ }) -join ' '))
    $rc  = Rm9Read (A '60000000') 4
    W ('raw DBI   0x0: ' + (($rc  | ForEach-Object { '{0:X8}' -f $_ }) -join ' '))
    $p   = Rm9Read (A '01C001B0') 1
    W ('raw PARF 0x1B0: ' + ('{0:X8}' -f $p[0]))
    $d   = Rm9Read (A '6000072C') 1
    W ('raw DBI 0x72C: ' + ('{0:X8}' -f $d[0]))
} catch { W "raw err: $_" }
