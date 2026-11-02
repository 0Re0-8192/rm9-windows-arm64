@echo off
rem S:\rm9\run.cmd = URS function-role experiment 2: stay in RoleSwitchMode=2 (function) for 2 minutes with the PC cable connected,
rem dump the USBFN / UFX state, the ETW provider list and the System event log.  Watch the PC side with refs\pc_usbwatch.ps1.
set L=C:\rm9
call S:\rm9\timesync.cmd
if not exist C:\rm9\session mkdir C:\rm9\session
echo ==== role2 start %date% %time%
echo [etw providers matching usb/ufx/urs/ucm]
logman query providers | findstr /i "usb ufx urs ucm typec"
set K=HKLM\SYSTEM\CurrentControlSet\Enum\ACPI\QCOM0C8B\0\Device Parameters
echo [USBFN control key]
reg query "HKLM\SYSTEM\CurrentControlSet\Control\USBFN" /s
reg query "HKLM\SYSTEM\CurrentControlSet\Control\USB" /s
echo [set function role]
reg add "%K%" /v RoleSwitchMode /t REG_DWORD /d 2 /f
> C:\rm9\session\fn_providers.txt echo Microsoft-Windows-USB-UFX 0xFFFFFFFFFFFFFFFF 0xFF
>> C:\rm9\session\fn_providers.txt echo Microsoft-Windows-USB-URS 0xFFFFFFFFFFFFFFFF 0xFF
>> C:\rm9\session\fn_providers.txt echo Microsoft-Windows-Kernel-PnP 0xFFFFFFFFFFFFFFFF 0xFF
logman stop rm9fn -ets
logman create trace rm9fn -pf C:\rm9\session\fn_providers.txt -o C:\rm9\session\fn.etl -f bincirc -max 32 -ets
pnputil /restart-device "ACPI\QCOM0C8B\0"
ping -n 41 127.0.0.1 >nul
echo [after restart %time%]
powershell -NoProfile -Command "Get-PnpDevice | Where-Object { $_.InstanceId -like 'URS*' -or $_.InstanceId -like 'ACPI\QCOM0C8B*' -or $_.Class -like 'UsbFn*' -or $_.InstanceId -like 'USBFN*' } | Format-Table Class,Status,FriendlyName,InstanceId -AutoSize | Out-String -Width 250"
pnputil /enum-devices /class USBFunctionController /relations
pnputil /enum-devices /instanceid "ACPI\QCOM0C8B\0" /relations /properties
echo [Enum\USBFN]
reg query "HKLM\SYSTEM\CurrentControlSet\Enum\USBFN" /s
ping -n 121 127.0.0.1 >nul
echo [after 2 more minutes %time%]
powershell -NoProfile -Command "Get-PnpDevice | Where-Object { $_.InstanceId -like 'URS*' -or $_.Class -like 'UsbFn*' -or $_.InstanceId -like 'USBFN*' } | Format-Table Class,Status,FriendlyName,InstanceId -AutoSize | Out-String -Width 250"
echo [system events]
powershell -NoProfile -Command "Get-WinEvent -LogName System -MaxEvents 60 | Where-Object { $_.ProviderName -match 'USB|UFX|URS|Kernel-PnP|UserPnp|Wdf' } | ForEach-Object { '{0} {1} {2}: {3}' -f $_.TimeCreated.ToString('HH:mm:ss'), $_.ProviderName, $_.Id, ($_.Message -replace '\s+',' ') } | Select-Object -First 40"
logman stop rm9fn -ets
rem put the role back to host before leaving
reg add "%K%" /v RoleSwitchMode /t REG_DWORD /d 1 /f
echo ==== role2 done %date% %time%
shutdown /a
shutdown /r /t 3 /f
