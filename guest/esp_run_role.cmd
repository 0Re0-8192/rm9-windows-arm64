@echo off
rem S:\rm9\run.cmd = URS role experiment: cycle RoleSwitchMode on the Synopsys DRD (ACPI\QCOM0C8B\0), restart the node, log which child (&HOST / &FUNCTION) appears.
rem Keep the PC cable connected: if a USB function comes up the PC should see a new device (watch with refs\pc_usbwatch.ps1).
set L=C:\rm9
call S:\rm9\timesync.cmd
if not exist C:\rm9\session mkdir C:\rm9\session
echo ==== role experiment start %date% %time%
set K=HKLM\SYSTEM\CurrentControlSet\Enum\ACPI\QCOM0C8B\0\Device Parameters
reg query "%K%"
echo [children before]
powershell -NoProfile -Command "Get-PnpDevice | Where-Object { $_.InstanceId -like 'URS*' -or $_.InstanceId -like 'ACPI\QCOM0C8B*' -or $_.Class -like 'UsbFn*' } | Format-Table Class,Status,FriendlyName,InstanceId -AutoSize | Out-String -Width 250"
for %%V in (0 2 3 4 1) do call :try %%V
echo ==== role experiment done %date% %time%
shutdown /a
shutdown /r /t 3 /f
goto :eof

:try
echo.
echo ==== RoleSwitchMode=%1 at %time%
reg add "%K%" /v RoleSwitchMode /t REG_DWORD /d %1 /f
pnputil /restart-device "ACPI\QCOM0C8B\0"
ping -n 31 127.0.0.1 >nul
echo [after restart, RoleSwitchMode=%1 at %time%]
powershell -NoProfile -Command "Get-PnpDevice | Where-Object { $_.InstanceId -like 'URS*' -or $_.InstanceId -like 'ACPI\QCOM0C8B*' -or $_.Class -like 'UsbFn*' -or $_.InstanceId -like 'USB\VID*' } | Format-Table Class,Status,FriendlyName,InstanceId -AutoSize | Out-String -Width 250"
pnputil /enum-devices /connected /class USB
goto :eof
