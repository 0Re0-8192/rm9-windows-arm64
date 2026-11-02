# S:\rm9\usbtest.ps1 - run as SYSTEM by esp_run_usbtest.cmd. Log policy: HANDOVER.md section 0.13.
# Every 5 s: heartbeat (NTFS + ESP copy), flush, temps, device snapshot (diff-only), HUD text for usbhud.ps1.  ETW + evtx + setupapi at the end / every 120 s.
param([int]$Seconds = 1320)
$dir = 'C:\rm9\session'
$pub = 'C:\Users\Public\rm9shot'
New-Item -ItemType Directory -Force -Path $dir, $pub | Out-Null
$t0 = Get-Date
$end = $t0.AddSeconds($Seconds)
$prev = ''
$lastChange = '-'
$lastEvt = Get-Date '2000-01-01'
function Phase($e) {
    if ($e -lt 180) { return 'PHASE 1: PC cable still connected - checking boot' }
    if ($e -lt 900) { return 'PHASE 2: NOW unplug the PC cable and connect [powered hub +] USB flash drive (or OTG adapter + flash drive)' }
    if ($e -lt 1200) { return 'PHASE 3: reconnect the PC cable (data cable)' }
    return 'PHASE 4: finishing - phone restarts into Android by itself'
}
while ((Get-Date) -lt $end) {
    $e = [int]((Get-Date) - $t0).TotalSeconds
    $stamp = Get-Date -Format 'HH:mm:ss'
    Add-Content -Path "$dir\alive.txt" -Value "$stamp t=$e" -ErrorAction SilentlyContinue
    try { Add-Content -Path 'S:\rm9\alive_esp.txt' -Value "$stamp t=$e" -ErrorAction Stop } catch {}
    $t = @()
    try {
        $t = @(Get-CimInstance -Namespace root/wmi -ClassName MSAcpi_ThermalZoneTemperature -ErrorAction Stop | ForEach-Object { [math]::Round($_.CurrentTemperature / 10 - 273.15, 1) })
        Add-Content -Path "$dir\temps.txt" -Value "$stamp $($t -join ' ')"
        if (($t | Measure-Object -Maximum).Maximum -ge 85) { Add-Content -Path "$dir\changes.txt" -Value "--- TOO HOT ($($t -join ' ')) - restarting"; shutdown /a; shutdown /r /t 2 /f; break }
    } catch {}
    $dev = @(Get-PnpDevice -PresentOnly -ErrorAction SilentlyContinue |
        Where-Object { $_.Class -in 'USB', 'USBDevice', 'DiskDrive', 'HIDClass', 'Keyboard', 'Mouse', 'Net', 'Volume', 'WPD', 'CDROM' -or $_.InstanceId -like 'USB*' } |
        Sort-Object InstanceId)
    $lines = $dev | ForEach-Object { '{0} | {1} | {2} | {3}' -f $_.Class, $_.Status, $_.FriendlyName, $_.InstanceId }
    $now = $lines -join "`r`n"
    if ($now -ne $prev) {
        $lastChange = $stamp
        $sb = "--- change at $stamp (t=$e s)`r`n$now`r`n"
        try { $sb += (pnputil /enum-devices /connected /class USB | Out-String) } catch {}
        try { $sb += (Get-Disk | Format-Table Number, FriendlyName, BusType, OperationalStatus, Size -AutoSize | Out-String) } catch {}
        try {
            foreach ($v in @(Get-Volume | Where-Object { $_.DriveLetter -and $_.DriveLetter -notin 'C', 'S' })) {
                $sb += "volume $($v.DriveLetter): $($v.FileSystemLabel) $($v.FileSystem) $($v.Size)`r`n"
                # read-only: names only, never write to the user's USB drive
                try { $sb += ((Get-ChildItem -LiteralPath "$($v.DriveLetter):\" -ErrorAction Stop | Select-Object -First 30 | ForEach-Object { '   ' + $_.Name + ' ' + $_.Length }) -join "`r`n") + "`r`n" } catch { $sb += "   (list failed: $($_.Exception.Message))`r`n" }
            }
        } catch {}
        try { $sb += (Get-NetAdapter | Format-Table Name, InterfaceDescription, Status, LinkSpeed -AutoSize | Out-String) } catch {}
        Add-Content -Path "$dir\changes.txt" -Value $sb
        $prev = $now
    }
    # HUD text for the on-screen viewer
    $usbN = @($dev | Where-Object { $_.InstanceId -like 'USB*' -and $_.InstanceId -notlike '*ROOT_HUB*' }).Count
    $hud = @("rm9 USB test   $stamp   t=$e s / $Seconds s", (Phase $e), '', "USB devices (excl. root hub): $usbN    last change: $lastChange", "temps: $($t -join ' ')", '')
    $internal = @($dev | Where-Object { $_.Class -eq 'DiskDrive' -and $_.InstanceId -like 'SCSI*' }).Count
    $hud += "internal UFS disks: $internal"
    $hud += ($dev | Where-Object { $_.Class -in 'DiskDrive', 'HIDClass', 'Keyboard', 'Mouse', 'Net', 'WPD', 'CDROM' -and $_.InstanceId -notlike 'SCSI*' -or $_.InstanceId -like 'USB\VID*' } | ForEach-Object { '{0}: {1}' -f $_.Class, $_.FriendlyName })
    try { $hud += (Get-Volume | Where-Object { $_.DriveLetter -and $_.DriveLetter -notin 'C', 'S' } | ForEach-Object { 'volume {0}: {1} {2} {3} GB' -f $_.DriveLetter, $_.FileSystemLabel, $_.FileSystem, [math]::Round($_.Size / 1GB, 1) }) } catch {}
    try { Set-Content -Path "$pub\hud.txt" -Value ($hud -join "`r`n") } catch {}
    try { Write-VolumeCache -DriveLetter C } catch {}
    if (((Get-Date) - $lastEvt).TotalSeconds -ge 120) {
        wevtutil epl System "$dir\System.evtx" /ow:true 2>$null
        $lastEvt = Get-Date
    }
    Start-Sleep -Seconds 5
}
Add-Content -Path "$dir\changes.txt" -Value "--- test ended $(Get-Date -Format 'HH:mm:ss')"
wevtutil epl System "$dir\System.evtx" /ow:true 2>$null
Copy-Item 'C:\Windows\INF\setupapi.dev.log' "$dir\setupapi.dev.log" -Force -ErrorAction SilentlyContinue
try { Write-VolumeCache -DriveLetter C } catch {}
