# C:\rm9\link\linksnap.ps1 (SYSTEM, boot task rm9linksnap): the QSCRATCH VBUS/session overrides the USB function needs (Windows resets them), applied ~20 s after boot, then repeated every 60 s
# (harmless writes of the same values) so a PC re-plug is also covered.  Uses the rm9io kernel driver (service started here).
param([int]$Seconds = 8640000)
cmd /c "sc start rm9io" | Out-Null
. C:\rm9\link\rm9io.ps1
$U = [uint64]0xA600000; $Q = $U + 0xF8800
function L($m) {
    $fs = New-Object IO.FileStream('C:\rm9\link\linksnap.txt', [IO.FileMode]::Append, [IO.FileAccess]::Write, [IO.FileShare]::ReadWrite, 4096, [IO.FileOptions]::WriteThrough)
    $b = [Text.Encoding]::ASCII.GetBytes(("{0} {1}`r`n" -f (Get-Date -Format 'HH:mm:ss'), $m)); $fs.Write($b, 0, $b.Length); $fs.Dispose()
}
L 'start'
Start-Sleep 20
$sw = [Diagnostics.Stopwatch]::StartNew(); $n = 0
while ($sw.Elapsed.TotalSeconds -lt $Seconds) {
    try {
        Rm9Write ($Q + 0x10) 0x10100000 0x10100000
        Rm9Write ($Q + 0x30) 0x01000000 0x01000000
        Rm9Write ($Q + 0x08) 0x2 0x2
        if ($n -eq 0) { L 'applied QSCRATCH overrides' }
        $n++
    } catch { L ("failed: " + $_.Exception.Message) }
    Start-Sleep 60
}
