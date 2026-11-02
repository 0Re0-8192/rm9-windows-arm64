@echo off
rem S:\rm9\run.cmd = collect the full Windows-side USB picture (host role): devices, resources, power, driver stack, registry, event log, Type-C (UCM) presence.
rem Output: C:\rm9\session\usbinfo.txt (+ run_out.txt).  Puts RoleSwitchMode back to host (1) first.
set L=C:\rm9
call S:\rm9\timesync.cmd
if not exist C:\rm9\session mkdir C:\rm9\session
echo ==== usbinfo start %date% %time%
set K=HKLM\SYSTEM\CurrentControlSet\Enum\ACPI\QCOM0C8B\0\Device Parameters
reg add "%K%" /v RoleSwitchMode /t REG_DWORD /d 1 /f
pnputil /restart-device "ACPI\QCOM0C8B\0"
ping -n 21 127.0.0.1 >nul
del C:\rm9\session\usbinfo.txt
powershell -NoProfile -ExecutionPolicy Bypass -File S:\rm9\usbinfo.ps1
type C:\rm9\session\usbinfo.txt
echo ==== usbinfo done %date% %time%
shutdown /a
shutdown /r /t 3 /f
