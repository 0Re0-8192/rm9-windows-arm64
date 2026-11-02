# S:\rm9\usbwatch.ps1 - watch the USB / disk / HID devices Windows sees for N seconds and log every change to C:\rm9\usb\changes.txt
param([int]$Seconds = 540)
$dir = 'C:\rm9\usb'
New-Item -ItemType Directory -Force -Path $dir | Out-Null
$end = (Get-Date).AddSeconds($Seconds)
$prev = ''
$n = 0
while ((Get-Date) -lt $end) {
    $n++
    $now = (Get-PnpDevice -PresentOnly -ErrorAction SilentlyContinue |
        Where-Object { $_.Class -in 'USB', 'USBDevice', 'DiskDrive', 'HIDClass', 'Keyboard', 'Mouse', 'WPD', 'Net', 'CDROM', 'Volume' -or $_.InstanceId -like 'USB*' } |
        Sort-Object InstanceId |
        ForEach-Object { '{0} | {1} | {2} | {3}' -f $_.Class, $_.Status, $_.FriendlyName, $_.InstanceId }) -join "`r`n"
    if ($now -ne $prev) {
        $stamp = Get-Date -Format 'HH:mm:ss'
        Add-Content -Path "$dir\changes.txt" -Value ("--- change at $stamp (poll $n)`r`n" + $now)
        try { Get-Disk | Format-Table Number, FriendlyName, BusType, OperationalStatus, Size -AutoSize | Out-String | Add-Content -Path "$dir\changes.txt" } catch {}
        try { Get-Volume | Format-Table DriveLetter, FileSystemLabel, FileSystem, Size -AutoSize | Out-String | Add-Content -Path "$dir\changes.txt" } catch {}
        $prev = $now
    }
    Add-Content -Path "$dir\alive.txt" -Value (Get-Date -Format 'HH:mm:ss') -ErrorAction SilentlyContinue
    Start-Sleep -Seconds 5
}
Add-Content -Path "$dir\changes.txt" -Value ("--- watch ended " + (Get-Date -Format 'HH:mm:ss'))
