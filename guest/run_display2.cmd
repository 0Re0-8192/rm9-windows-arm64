@echo off
rem display fix: show what Windows picked, then forget the stored (stale 640x680) display configuration so the next boot renegotiates
set L=C:\rm9
call S:\rm9\timesync.cmd
echo ==== run.cmd start %date% %time%
reg query "HKLM\SYSTEM\CurrentControlSet\Control\GraphicsDrivers\Configuration" /s | findstr /i "PrimSurfSize ActiveSize SetId"
reg query "HKLM\SYSTEM\CurrentControlSet\Control\GraphicsDrivers\Connectivity" /s | findstr /i "PrimSurfSize ActiveSize"
powershell -NoProfile -ExecutionPolicy Bypass -Command "Get-CimInstance Win32_VideoController | Format-List Name,CurrentHorizontalResolution,CurrentVerticalResolution,AdapterRAM"
reg delete "HKLM\SYSTEM\CurrentControlSet\Control\GraphicsDrivers\Configuration" /f
reg delete "HKLM\SYSTEM\CurrentControlSet\Control\GraphicsDrivers\Connectivity" /f
reg delete "HKLM\SYSTEM\CurrentControlSet\Control\GraphicsDrivers\ScaleFactors" /f
echo ==== run.cmd done %date% %time%
shutdown /a
shutdown /r /t 3 /f
