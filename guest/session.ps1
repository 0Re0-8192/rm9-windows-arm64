# S:\rm9\session.ps1 - every 10 s log the interactive state (logged-on users, explorer, session id) and every USB/HID/Net/Disk change to C:\rm9\session\
param([int]$Seconds = 2100)
$dir = 'C:\rm9\session'
New-Item -ItemType Directory -Force -Path $dir | Out-Null
$end = (Get-Date).AddSeconds($Seconds)
$prev = ''
$prevU = ''
while ((Get-Date) -lt $end) {
    $u = (& query user 2>&1 | Out-String).Trim()
    $ex = @(Get-Process explorer -ErrorAction SilentlyContinue).Count
    $state = "explorer=$ex`r`n$u"
    if ($state -ne $prevU) {
        Add-Content -Path "$dir\users.txt" -Value ("--- " + (Get-Date -Format 'HH:mm:ss') + "`r`n" + $state)
        $prevU = $state
    }
    $now = (Get-PnpDevice -PresentOnly -ErrorAction SilentlyContinue |
        Where-Object { $_.Class -in 'USB', 'USBDevice', 'DiskDrive', 'HIDClass', 'Keyboard', 'Mouse', 'Net', 'Volume', 'Bluetooth' -or $_.InstanceId -like 'USB*' } |
        Sort-Object InstanceId |
        ForEach-Object { '{0} | {1} | {2} | {3}' -f $_.Class, $_.Status, $_.FriendlyName, $_.InstanceId }) -join "`r`n"
    if ($now -ne $prev) {
        Add-Content -Path "$dir\changes.txt" -Value ("--- change at " + (Get-Date -Format 'HH:mm:ss') + "`r`n" + $now)
        try { Get-NetAdapter | Format-Table Name, InterfaceDescription, Status, LinkSpeed -AutoSize | Out-String | Add-Content -Path "$dir\changes.txt" } catch {}
        $prev = $now
    }
    try {
        $t = @(Get-CimInstance -Namespace root/wmi -ClassName MSAcpi_ThermalZoneTemperature -ErrorAction Stop | ForEach-Object { [math]::Round($_.CurrentTemperature / 10 - 273.15, 1) })
        Add-Content -Path "$dir\temps.txt" -Value ((Get-Date -Format 'HH:mm:ss') + ' ' + ($t -join ' '))
        if (($t | Measure-Object -Maximum).Maximum -ge 85) { Add-Content -Path "$dir\changes.txt" -Value "--- TOO HOT ($($t -join ' ')) - restarting"; shutdown /a; shutdown /r /t 2 /f; break }
    } catch {}
    Add-Content -Path "$dir\alive.txt" -Value (Get-Date -Format 'HH:mm:ss') -ErrorAction SilentlyContinue
    Start-Sleep -Seconds 10
}
Add-Content -Path "$dir\changes.txt" -Value ("--- session ended " + (Get-Date -Format 'HH:mm:ss'))
