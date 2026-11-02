@echo off
echo ==== thermal test start %date% %time%
shutdown /a
shutdown /r /t 300 /f
powershell -NoProfile -ExecutionPolicy Bypass -Command "Get-CimInstance -Namespace root/wmi -ClassName MSAcpi_ThermalZoneTemperature | ForEach-Object { '{0} : {1:N1} C  (crit {2:N1} C)' -f $_.InstanceName, ($_.CurrentTemperature/10-273.15), ($_.CriticalTripPoint/10-273.15) }"
echo [thermal zone perf counters]
powershell -NoProfile -ExecutionPolicy Bypass -Command "Get-CimInstance Win32_PerfFormattedData_Counters_ThermalZoneInformation | Format-List Name,Temperature,HighPrecisionTemperature,PercentPassiveLimit"
echo [pnp ThermalZone devices]
pnputil /enum-devices /class System | findstr /i "thermal"
powershell -NoProfile -ExecutionPolicy Bypass -Command "Get-PnpDevice -PresentOnly | Where-Object { $_.InstanceId -like 'ACPI\ThermalZone*' } | Format-Table Status,FriendlyName,InstanceId -AutoSize | Out-String -Width 200"
echo [CPU load then re-read: heat for ~40 s]
powershell -NoProfile -ExecutionPolicy Bypass -Command "$j = 1..8 | ForEach-Object { Start-Job { $e=(Get-Date).AddSeconds(40); while((Get-Date) -lt $e){ [Math]::Sqrt(12345.678) | Out-Null } } }; Start-Sleep 38; Get-CimInstance -Namespace root/wmi -ClassName MSAcpi_ThermalZoneTemperature | ForEach-Object { '{0} : {1:N1} C (under load)' -f $_.InstanceName, ($_.CurrentTemperature/10-273.15) }; $j | Stop-Job -ErrorAction SilentlyContinue"
echo ==== thermal test done %date% %time%
shutdown /a
shutdown /r /t 3 /f
