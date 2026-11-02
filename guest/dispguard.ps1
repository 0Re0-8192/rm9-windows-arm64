# S:\rm9\dispguard.ps1 (SYSTEM, first thing in run.cmd when C:\rm9\disp\trial.flag exists and ok.flag does not):
# trial.flag holds the number of boots started with the experimental display driver installed.
#   "0"  -> the install boot is over; this boot is the first one that loads the new driver: count it ("1"), keep the driver (touchsup writes ok.flag when the compositor runs fine).
#   "1"  -> the previous boot with the new driver never reached ok.flag (crash / frozen / slow): take the driver off again and remember that (failed.flag), so it is not reinstalled by itself.
$d = 'C:\rm9\disp'
function W($m) {
    $fs = New-Object IO.FileStream("$d\install.log", [IO.FileMode]::Append, [IO.FileAccess]::Write, [IO.FileShare]::ReadWrite, 4096, [IO.FileOptions]::WriteThrough)
    $b = [Text.Encoding]::ASCII.GetBytes("$(Get-Date -Format 'HH:mm:ss') guard: $m`r`n"); $fs.Write($b, 0, $b.Length); $fs.Dispose()
}
$v = (Get-Content "$d\trial.flag" -ErrorAction SilentlyContinue | Select-Object -First 1)
W "trial.flag=$v ok=$(Test-Path "$d\ok.flag")"
if ($v -eq '0') {
    [IO.File]::WriteAllText("$d\trial.flag", '1')
} else {
    W "the driver did not reach ok.flag in its first boot -> reverting"
    & S:\rm9\dispinstall.ps1 -Revert
    'failed' | Out-File "$d\failed.flag" -Encoding ascii
}
