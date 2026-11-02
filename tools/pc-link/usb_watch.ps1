# Log any appearance of the phone on USB (EDL 9008 / ZTE dump 0112 / charge FFCC / ADB / fastboot) with timestamps.
# usage: powershell -File usb_watch.ps1 [minutes]   -> winboot\usb_watch.log
param([int]$Minutes = 60)
$log = '<RM9_WORKDIR>\winboot\usb_watch.log'
$end = (Get-Date).AddMinutes($Minutes)
$prev = ''
"start $(Get-Date -Format s)" | Add-Content $log
while ((Get-Date) -lt $end) {
    $cur = (Get-PnpDevice -PresentOnly -ErrorAction SilentlyContinue |
        Where-Object { $_.InstanceId -match 'VID_19D2|VID_18D1|VID_05C6|VID_22B8' } |
        ForEach-Object { $_.InstanceId.Split('\')[1] + ' ' + $_.FriendlyName }) -join ' | '
    if ($cur -ne $prev) {
        "$(Get-Date -Format s)  $(if ($cur) { $cur } else { '(none)' })" | Add-Content $log
        $prev = $cur
    }
    Start-Sleep -Milliseconds 500
}
"end $(Get-Date -Format s)" | Add-Content $log
