# keyprobe.ps1 - read-only probe of the phone's keys through the PMIC (run as SYSTEM; needs the rm9io service):
#   power key   PMK8550 sid0 PON_HLOS 0x1300: PON_RT_STS (0x10) bit0 = KPDPWR_N (pressed = 1), bit1 = RESIN_N (volume down, pressed = 1)
#   volume up   PM8550 sid1 GPIO6 (pinctrl@8800 -> base 0x8D00): GPIO_STATUS (0x08) bit0 = pin level (active low: pressed = 0)
# Prints the registers once, then every change for -Seconds seconds (press the keys meanwhile).  Output: C:\rm9\keyprobe.txt
param([int]$Seconds = 40)
$root = Split-Path -Parent $MyInvocation.MyCommand.Path
. "$root\spmi.ps1"
if ((Get-Service rm9io -ErrorAction SilentlyContinue).Status -ne "Running") { Start-Service rm9io -ErrorAction SilentlyContinue; Start-Sleep 1 }
$out = "C:\rm9\keyprobe.txt"
New-Item -ItemType Directory -Force C:\rm9 | Out-Null
function Log($m) { "$(Get-Date -Format HH:mm:ss.fff) $m" | Out-File -Append -Encoding ascii $out }
"" | Out-File -Encoding ascii $out
try { $n = Spmi-Init; Log "apids mapped (EE0-readable): $n" } catch { Log "init failed: $_"; exit 1 }
function Hex($b) { if ($b -eq $null) { "--" } else { ($b | ForEach-Object { "{0:X2}" -f $_ }) -join " " } }
Log ("PON  0x1300 type/subtype: " + (Hex (Spmi-Read 0 0x1304 2)))
Log ("PON  0x1308..0x1318    : " + (Hex (Spmi-Read 0 0x1308 8)) + " | " + (Hex (Spmi-Read 0 0x1310 8)))
Log ("GPIO6 0x8D00 type/sub   : " + (Hex (Spmi-Read 1 0x8D04 2)))
Log ("GPIO6 status/mode/pull/en: " + (Hex (Spmi-Read 1 0x8D08 1)) + " | " + (Hex (Spmi-Read 1 0x8D40 1)) + " | " + (Hex (Spmi-Read 1 0x8D42 1)) + " | " + (Hex (Spmi-Read 1 0x8D46 1)))
Log ("RTC seconds (sid0 0x6148): " + (Hex (Spmi-Read 0 0x6148 4)))
$lastPon = -1; $lastGpio = -1
$t0 = Get-Date
while (((Get-Date) - $t0).TotalSeconds -lt $Seconds) {
    $p = Spmi-Read 0 0x1310 1
    $g = Spmi-Read 1 0x8D08 1
    $pv = if ($p) { $p[0] } else { -2 }
    $gv = if ($g) { $g[0] -band 1 } else { -2 }
    if ($pv -ne $lastPon -or $gv -ne $lastGpio) {
        Log ("PON_RT_STS=0x{0:X2} (power={1} voldown={2})  GPIO6 level={3} (volup pressed={4})" -f $pv, ($pv -band 1), (($pv -shr 1) -band 1), $gv, [int]($gv -eq 0))
        $lastPon = $pv; $lastGpio = $gv
    }
    Start-Sleep -Milliseconds 30
}
Log "done"
