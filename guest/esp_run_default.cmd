@echo off
rem S:\rm9\run.cmd on the ESP: the editable experiment script.  Output of this script goes to C:\rm9\run_out.txt (see rm9_boot.cmd).
set L=C:\rm9
call S:\rm9\timesync.cmd
echo ==== run.cmd start %date% %time%
rem the USB function experiments leave RoleSwitchMode=2; the default run goes back to host role (1) for the hub / USB-stick tests
reg add "HKLM\SYSTEM\CurrentControlSet\Enum\ACPI\QCOM0C8B\0\Device Parameters" /v RoleSwitchMode /t REG_DWORD /d 1 /f
echo hello> %L%\w2.txt
whoami
ver
echo [disks]
(echo list disk& echo list volume) > %TEMP%\rm9dp.txt
diskpart /s %TEMP%\rm9dp.txt
echo [problem devices]
pnputil /enum-devices /problem
echo [usb devices]
pnputil /enum-devices /class USB
echo [thermal zones]
powershell -NoProfile -ExecutionPolicy Bypass -Command "Get-CimInstance -Namespace root/wmi -ClassName MSAcpi_ThermalZoneTemperature | ForEach-Object { '{0} : {1:N1} C' -f $_.InstanceName, ($_.CurrentTemperature/10-273.15) }"
echo ==== run.cmd done %date% %time%
rem restart cleanly (cancel the 10 minute backstop first)
shutdown /a
shutdown /r /t 3 /f
