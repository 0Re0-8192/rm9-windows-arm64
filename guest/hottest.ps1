# hottest.ps1 - proves that a HOT SoC makes dbgcap.sys stop pinging the watchdog (and therefore resets the phone): lower the temperature limit to 30.0 C, which an idle Windows is always above.
# Expected: the log ends within ~31 s after "LIMIT LOWERED"; the phone returns to Android.  If it is still alive 90 s later the temperature protection did NOT work.
# Log: S:\rm9\hottest.txt (WriteThrough).  Runs after guard.cmd.
. S:\rm9\dbgcap.ps1
$fs = New-Object IO.FileStream('S:\rm9\hottest.txt', [IO.FileMode]::Append, [IO.FileAccess]::Write, [IO.FileShare]::ReadWrite, 4096, [IO.FileOptions]::WriteThrough)
function L($s) { $b = [Text.Encoding]::ASCII.GetBytes(((Get-Date -Format 'HH:mm:ss.fff') + ' ' + $s + "`r`n")); $fs.Write($b, 0, $b.Length); $fs.Flush() }
function Wdt([uint32]$stop, [uint32]$limit) {
    if (-not [DbgCap]::Open()) { return $null }
    $buf = New-Object byte[] 32
    [BitConverter]::GetBytes($stop).CopyTo($buf, 0); [BitConverter]::GetBytes($limit).CopyTo($buf, 4)
    $ret = 0
    $code = [Convert]::ToUInt32('8F002820', 16)
    try { $ok = [DbgCap]::DeviceIoControl([DbgCap]::H, $code, $buf, 8, $buf, 32, [ref]$ret, [IntPtr]::Zero) } catch { L ('ioctl threw: ' + $_.Exception.Message); return $null }
    if (-not $ok) { L 'ioctl failed'; return $null }
    return [pscustomobject]@{ On = [BitConverter]::ToUInt32($buf, 0); TempDc = [BitConverter]::ToInt32($buf, 4) }
}
L '=== hottest start'
$r = $null
for ($i = 0; $i -lt 30 -and -not $r; $i++) { $r = Wdt 0 0; if (-not $r) { Start-Sleep 2 } }
if (-not $r -or $r.On -ne 1) { L 'guard is not on - not testing'; $fs.Close(); exit 2 }
for ($i = 0; $i -lt 10; $i++) { Start-Sleep 1; $r = Wdt 0 0; L ('normal  hottest=' + ($r.TempDc / 10.0) + ' C (limit 100.0)') }
L '*** LIMIT LOWERED TO 30.0 C - the phone should reset within ~31 s ***'
$null = Wdt 0 300
$t0 = Get-Date
while (((Get-Date) - $t0).TotalSeconds -lt 90) { Start-Sleep 1; $r = Wdt 0 300; L ('after lowering +' + [int]((Get-Date) - $t0).TotalSeconds + ' s  hottest=' + ($r.TempDc / 10.0)) }
L 'FAIL: still alive 90 s after lowering the limit - the temperature protection did NOT reset the phone'
$null = Wdt 0 0
$fs.Close()
exit 4
