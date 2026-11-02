# ELEVATED (PC): remove stale VID_1209 phantom devnodes, trace the USB hub/xHCI stack with ETW while the phone's function device enumerates,
# log the PnP state of the device and try one restart of the failing child.  Output: <RM9_WORKDIR>\winboot\usbtrace\
param([int]$Seconds = 1300)
$o = '<RM9_WORKDIR>\winboot\usbtrace'; New-Item -ItemType Directory -Force $o | Out-Null
function L($m) { Add-Content "$o\admin.log" ("{0} {1}" -f (Get-Date -Format 'HH:mm:ss'), $m) }
L 'start'
# 1. phantoms
Get-PnpDevice -ErrorAction SilentlyContinue | Where-Object { $_.InstanceId -like 'USB\VID_1209&PID_000*' -and -not $_.Present } | ForEach-Object { L "remove $($_.InstanceId)"; pnputil /remove-device $_.InstanceId | Out-String | ForEach-Object { L $_ } }
# 2. ETW
logman stop rm9usb -ets 2>$null | Out-Null
$prov = @('Microsoft-Windows-USB-USBHUB3', 'Microsoft-Windows-USB-USBXHCI', 'Microsoft-Windows-USB-UCX', 'Microsoft-Windows-Kernel-PnP')
logman create trace rm9usb -ow -o "$o\usb.etl" -ets -nb 16 256 -bs 1024 | Out-String | ForEach-Object { L $_ }
foreach ($p in $prov) { logman update trace rm9usb -p $p 0xFFFFFFFFFFFFFFFF 0xFF -ets | Out-String | ForEach-Object { L ("provider $p : " + $_) } }
# 3. watch the device, try one restart of the child
$end = (Get-Date).AddSeconds($Seconds); $restarted = $false; $last = ''
while ((Get-Date) -lt $end) {
    $devs = Get-PnpDevice -PresentOnly -ErrorAction SilentlyContinue | Where-Object { $_.InstanceId -like 'USB\VID_1209&PID_000*' }
    $s = ($devs | ForEach-Object { '{0} status={1} problem={2}' -f $_.InstanceId, $_.Status, $_.Problem }) -join "`r`n"
    if ($s -ne $last) { L $s; $last = $s }
    $child = $devs | Where-Object { $_.InstanceId -like '*&MI_00*' }
    if ($child -and -not $restarted) {
        Start-Sleep 20
        L "pnputil /restart-device $($child.InstanceId)"
        pnputil /restart-device $child.InstanceId | Out-String | ForEach-Object { L $_ }
        $restarted = $true
        Start-Sleep 5
        $devs = Get-PnpDevice -PresentOnly | Where-Object { $_.InstanceId -like 'USB\VID_1209&PID_000*' }
        L (($devs | ForEach-Object { '{0} status={1} problem={2}' -f $_.InstanceId, $_.Status, $_.Problem }) -join "`r`n")
        $ifs = Get-ChildItem 'HKLM:\SYSTEM\CurrentControlSet\Control\DeviceClasses\{dee824ef-729b-4a0e-9c14-b7117d33a817}' | Where-Object PSChildName -match '1209' | ForEach-Object PSChildName
        L ("winusb interfaces: " + ($ifs -join ' '))
    }
    Start-Sleep 1
}
logman stop rm9usb -ets | Out-String | ForEach-Object { L $_ }
tracerpt "$o\usb.etl" -o "$o\usb.csv" -of CSV -summary "$o\usb_sum.txt" -y | Out-Null
L 'done'
