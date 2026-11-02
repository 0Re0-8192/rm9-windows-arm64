# wdttest.ps1 - proves that dbgcap.sys's watchdog guard really resets the phone when pinging stops.  Runs from esp_run_wdttest.cmd after "sc start dbgcap".
# Steps: (1) ask dbgcap whether the guard is ON and read the hottest TSENS value; if OFF, do nothing risky.  (2) log temperatures for ~20 s.  (3) tell dbgcap to stop pinging on purpose and log once a second
# until the hypervisor resets the phone (expected within ~31 s).  If the phone is still alive 90 s later the test FAILED: pings are resumed and the script ends (run.cmd then restarts Windows).
# Every line goes to S:\rm9\wdttest.txt with WriteThrough, so the last line shows when the reset hit.
. S:\rm9\dbgcap.ps1
$fs = New-Object IO.FileStream('S:\rm9\wdttest.txt', [IO.FileMode]::Append, [IO.FileAccess]::Write, [IO.FileShare]::ReadWrite, 4096, [IO.FileOptions]::WriteThrough)
function L($s) { $b = [Text.Encoding]::ASCII.GetBytes(((Get-Date -Format 'HH:mm:ss.fff') + ' ' + $s + "`r`n")); $fs.Write($b, 0, $b.Length); $fs.Flush() }
function Wdt([uint32]$stop) {
    if (-not [DbgCap]::Open()) { return $null }
    $buf = New-Object byte[] 224
    [BitConverter]::GetBytes($stop).CopyTo($buf, 0)
    $ret = 0
    # PowerShell reads 0x8F002820 as a NEGATIVE Int32 and then fails to convert it to uint, so the call never reached the driver (cycles 1-6): build the code as UInt32 explicitly
    $code = [Convert]::ToUInt32('8F002820', 16)
    $ok = $false
    try { $ok = [DbgCap]::DeviceIoControl([DbgCap]::H, $code, $buf, 4, $buf, 224, [ref]$ret, [IntPtr]::Zero) } catch { L ('DeviceIoControl threw: ' + $_.Exception.Message); return $null }
    if (-not $ok) { L ('DeviceIoControl failed, win32 error ' + [Runtime.InteropServices.Marshal]::GetLastWin32Error()); return $null }
    $script:lastRet = $ret; $script:lastHex = ([BitConverter]::ToString($buf)).Replace('-', '')
    return [pscustomobject]@{ On = [BitConverter]::ToUInt32($buf, 0); TempDc = [BitConverter]::ToInt32($buf, 4); Map = [BitConverter]::ToUInt32($buf, 8); T0 = [BitConverter]::ToInt32($buf, 12); En = [BitConverter]::ToUInt32($buf, 16); Ping = [BitConverter]::ToUInt32($buf, 20); Stage = [BitConverter]::ToUInt32($buf, 24); Loop = [BitConverter]::ToUInt32($buf, 28); Raw = $buf }
}
L '=== wdttest start'
$r = $null
for ($i = 0; $i -lt 30 -and -not $r; $i++) { $r = Wdt 0; if (-not $r) { Start-Sleep 2 } }
if (-not $r) { L 'FAIL: dbgcap IOCTL not available'; $fs.Close(); exit 1 }
L ('guard on=' + $r.On + ' hottest=' + ($r.TempDc / 10.0) + ' C')
L ('diag: tsens-mapped-mask=0x{0:X} hottest-at-start(dC)={1} hvc-enable-ret=0x{2:X8} hvc-ping-ret=0x{3:X8} thread-stage={4} thread-sec={5}' -f $r.Map, $r.T0, $r.En, $r.Ping, $r.Stage, $r.Loop)
L ('ioctl returned bytes=' + $script:lastRet)
$sv = New-Object System.Collections.Generic.List[string]
for ($b = 0; $b -lt 3; $b++) { for ($n = 0; $n -lt 16; $n++) { $w = [BitConverter]::ToUInt32($r.Raw, 32 + 4 * ($b * 16 + $n)); if ($w -band 0x200000) { $t = $w -band 0xFFF; if ($t -band 0x800) { $t -= 0x1000 }; $sv.Add('{0}.{1}={2}' -f $b, $n, ($t / 10.0)) } } }
L ('tsens (block.sensor=C): ' + ($sv -join ' '))
try { $dbg = [DbgCap]::Read(); if ($dbg.Length -gt 700) { $dbg = $dbg.Substring(0, 700) }; L ('dbgcap ring head: ' + ($dbg -replace '[\r\n]+', ' | ')) } catch { L ('ring read failed: ' + $_) }
if ($r.On -ne 1) { L 'guard is OFF (HVC enable failed or no TSENS) - not testing the reset'; $fs.Close(); exit 2 }
if ($r.TempDc -ge 1000) { L 'too warm to start the test (>= 100 C)'; $fs.Close(); exit 3 }
for ($i = 0; $i -lt 20; $i++) { Start-Sleep 1; $r = Wdt 0; L ('normal  on=' + $r.On + ' hottest=' + ($r.TempDc / 10.0)) }
L '*** STOPPING PINGS ON PURPOSE - the phone should reset within ~31 s ***'
$null = Wdt 1
$t0 = Get-Date
while (((Get-Date) - $t0).TotalSeconds -lt 90) {
    Start-Sleep -Seconds 1
    $r = Wdt 1
    L ('after stop +' + [int]((Get-Date) - $t0).TotalSeconds + ' s  hottest=' + ($r.TempDc / 10.0))
}
L 'FAIL: still alive 90 s after stopping the pings - the watchdog did NOT reset the phone'
$null = Wdt 0
$fs.Close()
exit 4
