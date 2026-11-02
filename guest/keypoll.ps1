# C:\rm9\link\keypoll.ps1 (SYSTEM task rm9keypoll): poll the phone's three keys through the PMIC (read-only, see spmi.ps1) and publish the pressed-mask.
#   C:\Users\Public\rm9shot\keys.cur   one line, overwritten on every change: "seq;mask"   mask bit0 = volume up, bit1 = volume down, bit2 = power
#   volume up   PM8550 sid1 GPIO6 (0x8D00) GPIO_STATUS (0x08) bit0 = level, active low
#   volume down PMK8550 sid0 PON_HLOS (0x1300) PON_RT_STS (0x10) bit6 (0x40)
#   power       same register, bit7 (0x80)           (bit4 = 0x10 is always set and is not a key)   [measured 2026-10-21, rm9\keyprobe.txt]
param([int]$Seconds = 8640000)
$root = Split-Path -Parent $MyInvocation.MyCommand.Path
. "$root\spmi.ps1"
if ((Get-Service rm9io -ErrorAction SilentlyContinue).Status -ne "Running") { Start-Service rm9io -ErrorAction SilentlyContinue; Start-Sleep 1 }
New-Item -ItemType Directory -Force C:\rm9, C:\Users\Public\rm9shot | Out-Null
$cur = "C:\Users\Public\rm9shot\keys.cur"
$log = "C:\rm9\keypoll.log"
function Log($m) { "$(Get-Date -Format 'MM-dd HH:mm:ss') $m" | Out-File -Append -Encoding ascii $log }
function Publish($seq, $mask) {
    $b = [Text.Encoding]::ASCII.GetBytes("$seq;$mask`r`n")
    $fs = New-Object IO.FileStream($cur, [IO.FileMode]::Create, [IO.FileAccess]::Write, [IO.FileShare]::ReadWrite)
    $fs.Write($b, 0, $b.Length); $fs.Dispose()
}
$n = 0
for ($try = 0; $try -lt 20 -and $n -eq 0; $try++) { try { $n = Spmi-Init } catch { Log "init: $_" }; if ($n -eq 0) { Start-Sleep 3 } }
if ($n -eq 0) { Log "SPMI init failed - key poller not started"; exit 1 }
Log "key poller started ($n apids)"
$seq = 0; $last = -1; $fails = 0
$t0 = Get-Date
Publish 0 0
while (((Get-Date) - $t0).TotalSeconds -lt $Seconds) {
    $p = Spmi-Read 0 0x1310 1
    $g = Spmi-Read 1 0x8D08 1
    if ($p -eq $null -or $g -eq $null) {
        $fails++
        if ($fails -eq 50) { Log "reads failing (50 in a row)" }
        Start-Sleep -Milliseconds 100
        continue
    }
    $fails = 0
    $mask = 0
    if (($g[0] -band 1) -eq 0) { $mask = $mask -bor 1 }
    if ($p[0] -band 0x40) { $mask = $mask -bor 2 }
    if ($p[0] -band 0x80) { $mask = $mask -bor 4 }
    if ($mask -ne $last) {
        $seq++
        Publish $seq $mask
        $last = $mask
    }
    Start-Sleep -Milliseconds 20
}
