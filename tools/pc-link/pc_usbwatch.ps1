# Run on the PC: log every change of the connected USB devices (VID/PID, name) with a timestamp until stopped or -Seconds elapsed.
# Use it while the phone runs a Windows experiment (esp_run_role.cmd) to see whether the phone shows up on the PC as a USB function.
param([int]$Seconds = 1200, [string]$Out = '<RM9_WORKDIR>\winboot\pc_usbwatch.txt')
$prev = @{}
$end = (Get-Date).AddSeconds($Seconds)
Add-Content $Out "--- start $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
while ((Get-Date) -lt $end) {
    $now = @{}
    Get-PnpDevice -PresentOnly -ErrorAction SilentlyContinue | Where-Object { $_.InstanceId -like 'USB\VID_*' } | ForEach-Object { $now[$_.InstanceId] = '{0} | {1}' -f $_.Class, $_.FriendlyName }
    foreach ($k in $now.Keys) { if (-not $prev.ContainsKey($k)) { Add-Content $Out ('{0} + {1} {2}' -f (Get-Date -Format 'HH:mm:ss'), $k, $now[$k]) } }
    foreach ($k in $prev.Keys) { if (-not $now.ContainsKey($k)) { Add-Content $Out ('{0} - {1} {2}' -f (Get-Date -Format 'HH:mm:ss'), $k, $prev[$k]) } }
    $prev = $now
    Start-Sleep -Seconds 1
}
Add-Content $Out "--- end $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
