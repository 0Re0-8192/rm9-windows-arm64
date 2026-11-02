@echo off
rem S:\rm9\run.cmd = USB function experiment 7 (two boots).  Boot 1: write the USBFN config + RoleSwitchMode=2 and reboot (a live restart of the host stack fails with
rem "System reboot is needed" once the dwc3 glue overrides are set).  Boot 2 (flag file present): the controller comes up as USB function; activate the bus and hold.
rem Run both boots with  phone_setup_loop.ps1 -UsbFn  (MuChain sets the QSCRATCH VBUS/session overrides before Windows).  Watch the PC with refs\pc_usbwatch.ps1.
set L=C:\rm9
call S:\rm9\timesync.cmd
if not exist C:\rm9\session mkdir C:\rm9\session
set F=HKLM\SYSTEM\CurrentControlSet\Control\USBFN
set K=HKLM\SYSTEM\CurrentControlSet\Enum\ACPI\QCOM0C8B\0\Device Parameters
if exist C:\rm9\session\phase2.flag goto :phase2
reg query "%K%" /v RoleSwitchMode | find "0x2" >nul && goto :phase2

echo ==== role7 boot1 %date% %time%
for %%K in ("%F%" "%F%\Default") do (
  reg add %%K /v idVendor /t REG_DWORD /d 0x1209 /f
  reg add %%K /v idProduct /t REG_DWORD /d 0x0001 /f
  reg add %%K /v bcdDevice /t REG_DWORD /d 0x0100 /f
  reg add %%K /v bDeviceClass /t REG_DWORD /d 0 /f
  reg add %%K /v bDeviceSubclass /t REG_DWORD /d 0 /f
  reg add %%K /v bDeviceProtocol /t REG_DWORD /d 0 /f
  reg add %%K /v iSerialNumber /t REG_DWORD /d 0 /f
  reg add %%K /v ManufacturerString /t REG_SZ /d rm9 /f
  reg add %%K /v ProductString /t REG_SZ /d "RM9 Windows" /f
  reg add %%K /v SerialNumberString /t REG_SZ /d RM9WIN0001 /f
  reg add %%K /v ClassEndpointRequestEnabled /t REG_DWORD /d 0 /f
)
reg add "%F%" /v CurrentConfiguration /t REG_SZ /d Rm9 /f
reg add "%F%" /v IncludeDefaultCfg /t REG_DWORD /d 0 /f
for %%C in (Rm9 Default) do (
  reg add "%F%\Configurations\%%C" /v InterfaceList /t REG_MULTI_SZ /d GENERICUSBFN /f
  reg add "%F%\Configurations\%%C" /v MSOSCompatIdDescriptor /t REG_BINARY /d 28000000000104000100000000000000000157494E55534200000000000000000000000000000000 /f
  reg add "%F%\Configurations\%%C" /v bmAttributes /t REG_DWORD /d 0x80 /f
  reg add "%F%\Configurations\%%C" /v bMaxPower /t REG_DWORD /d 250 /f
)
reg add "%F%\Interfaces\GENERICUSBFN" /v InterfaceDescriptor /t REG_BINARY /d 0904000002FF0000000705810200020007050102000200 /f
reg add "%F%\Interfaces\GENERICUSBFN" /v InterfaceGUID /t REG_SZ /d {7a1f2c3e-5b6d-4e8f-9a0b-1c2d3e4f5a6b} /f
reg add "%K%" /v RoleSwitchMode /t REG_DWORD /d 2 /f
echo phase2> C:\rm9\session\phase2.flag
echo ==== role7 boot1 done, rebooting into function role
shutdown /a
shutdown /r /t 3 /f
goto :eof

:phase2
del C:\rm9\session\phase2.flag
echo ==== role7 boot2 %date% %time%
> C:\rm9\session\fn_providers.txt echo {E98EBDBF-3058-4784-8521-47860B1D2B8E} 0xFFFFFFFFFFFFFFFF 0xFF
>> C:\rm9\session\fn_providers.txt echo {49B12C7C-4BD5-4F93-BB75-30FCE739600B} 0xFFFFFFFFFFFFFFFF 0xFF
logman stop rm9fn -ets
logman create trace rm9fn -pf C:\rm9\session\fn_providers.txt -o C:\rm9\session\fn.etl -f bincirc -max 32 -ets
reg query "%K%"
call :status boot2-start
start "" /b powershell -NoProfile -ExecutionPolicy Bypass -File S:\rm9\usbfn_activate.ps1 -Seconds 200
ping -n 61 127.0.0.1 >nul
call :status 60s
ping -n 61 127.0.0.1 >nul
call :status 120s
ping -n 61 127.0.0.1 >nul
call :status 180s
ping -n 61 127.0.0.1 >nul
call :status 240s
type C:\rm9\session\activate.txt
logman stop rm9fn -ets
rem keep the function role (RoleSwitchMode=2) so that the next boot starts in device mode directly (set it back to 1 for host use)
echo ==== role7 boot2 done %date% %time%
shutdown /a
shutdown /r /t 3 /f
goto :eof

:status
echo [status %1 at %time%]
powershell -NoProfile -Command "Get-PnpDevice | Where-Object { $_.InstanceId -like 'URS*' -or $_.InstanceId -like 'USBFN*' -or $_.Class -like 'UsbFn*' -or $_.InstanceId -like 'ACPI\QCOM0C8B*' } | Format-Table Class,Status,FriendlyName,InstanceId -AutoSize | Out-String -Width 250"
goto :eof
