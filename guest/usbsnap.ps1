# S:\rm9\usbsnap.ps1 -Seconds N : (SYSTEM) only LOG the DWC3 / glue state every 2 s with write-through (no register is written): used when the function stack was started at boot on PHYs prepared by MuChain (USBPREP).
param([int]$Seconds = 300, [switch]$Override)
function Add-Content {
    param([Parameter(Position = 0)]$Path, [Parameter(Position = 1)]$Value)
    $fs = New-Object IO.FileStream($Path, [IO.FileMode]::Append, [IO.FileAccess]::Write, [IO.FileShare]::ReadWrite, 4096, [IO.FileOptions]::WriteThrough)
    $b = [Text.Encoding]::ASCII.GetBytes("$Value`r`n"); $fs.Write($b, 0, $b.Length); $fs.Dispose()
}
. S:\rm9\rm9io.ps1
$log = 'C:\rm9\session\usbsnap.txt'
$U = [uint64]0xA600000; $Q = $U + 0xF8800; $G = [uint64]0x100000
function R1([uint64]$a) { (Rm9Read $a 1)[0] }
function L($m) { Add-Content -Path $log -Value ('{0} {1}' -f (Get-Date -Format 'HH:mm:ss.ff'), $m) }
L '##### usbsnap start'
$sw = [Diagnostics.Stopwatch]::StartNew()
$prev = ''
while ($sw.Elapsed.TotalSeconds -lt $Seconds) {
    try {
        $dcfg = R1 ($U + 0xC700); $dctl = R1 ($U + 0xC704); $dsts = R1 ($U + 0xC70C); $gctl = R1 ($U + 0xC110)
        $ev0 = R1 ($U + 0xC40C); $q10 = R1 ($Q + 0x10); $q58 = R1 ($Q + 0x58); $ltssm = R1 ($U + 0xC164); $dt = R1 ($U + 0xC708)
        $pcs = R1 (0x88E8000 + 0x1C14)
        $key = ('GCTL={0:X8} DCFG={1:X8} DCTL={2:X8} DEVTEN={3:X8} DSTS={4:X8} EVCNT0={5} Q10={6:X8} Q58={7:X8} LTSSM={8:X8} PCS={9:X8} bcr phy={10:X} dp={11:X}' -f $gctl, $dcfg, $dctl, $dt, ($dsts -band 0xFFFFF), $ev0, $q10, $q58, $ltssm, $pcs, (R1 ($G + 0x50000)), (R1 ($G + 0x50008)))
        if ($key -ne $prev) { L $key; $prev = $key }
    } catch { L ("read failed: " + $_.Exception.Message) }
    if ($Override -and -not $done -and $sw.Elapsed.TotalSeconds -gt 15) {
        $done = $true
        Rm9Write ($Q + 0x10) 0x10100000 0x10100000
        Rm9Write ($Q + 0x30) 0x01000000 0x01000000
        Rm9Write ($Q + 0x08) 0x2 0x2
        L 'applied: QSCRATCH VBUS/session overrides (only)'
    }
    Start-Sleep -Seconds 2
}
L '##### usbsnap done'
