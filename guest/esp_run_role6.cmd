@echo off
rem S:\rm9\run.cmd = USB function (device-mode) experiment 3: define a USBFN configuration (vendor-specific interface, 2 bulk endpoints, WINUSB compat id),
rem switch the Synopsys DRD to the function role (RoleSwitchMode=2), restart it, and hold for ~4 minutes with the PC cable connected.
rem PC side: refs\pc_usbwatch.ps1 should log a new USB device VID_1209&PID_0001 ("RM9 Windows").  Schema: learn.microsoft.com ... usb-registry-settings-for-a-function-controller-driver
set L=C:\rm9
call S:\rm9\timesync.cmd
if not exist C:\rm9\session mkdir C:\rm9\session
echo ==== role6 start %date% %time%
set F=HKLM\SYSTEM\CurrentControlSet\Control\USBFN
set K=HKLM\SYSTEM\CurrentControlSet\Enum\ACPI\QCOM0C8B\0\Device Parameters
echo [write USBFN config]
reg add "%F%" /v idVendor /t REG_DWORD /d 0x1209 /f
reg add "%F%" /v idProduct /t REG_DWORD /d 0x0001 /f
reg add "%F%" /v ManufacturerString /t REG_SZ /d rm9 /f
reg add "%F%" /v ProductString /t REG_SZ /d "RM9 Windows" /f
reg add "%F%" /v CurrentConfiguration /t REG_SZ /d Rm9 /f
reg add "%F%" /v IncludeDefaultCfg /t REG_DWORD /d 0 /f
reg add "%F%\Configurations\Rm9" /v InterfaceList /t REG_MULTI_SZ /d GENERICUSBFN /f
rem Extended Compat ID descriptor: 40 bytes, 1 function (interface 0) -> WINUSB
reg add "%F%\Configurations\Rm9" /v MSOSCompatIdDescriptor /t REG_BINARY /d 28000000000104000100000000000000000157494E55534200000000000000000000000000000000 /f
rem Interface: class FF, 2 endpoints (bulk IN 0x81 / OUT 0x01, 512 bytes)
reg add "%F%\Interfaces\GENERICUSBFN" /v InterfaceDescriptor /t REG_BINARY /d 0904000002FF0000000705810200020007050102000200 /f
reg add "%F%\Interfaces\GENERICUSBFN" /v InterfaceGUID /t REG_SZ /d {7a1f2c3e-5b6d-4e8f-9a0b-1c2d3e4f5a6b} /f
rem --- role6: UFX failed with 0xC0000034 (name not found) while building descriptors: fill every value it reads, in USBFN and in the MS-owned USBFN\Default
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
reg add "%F%\Configurations\Rm9" /v bmAttributes /t REG_DWORD /d 0x80 /f
reg add "%F%\Configurations\Rm9" /v bMaxPower /t REG_DWORD /d 250 /f
reg add "%F%\Configurations\Default" /v InterfaceList /t REG_MULTI_SZ /d GENERICUSBFN /f
reg add "%F%\Configurations\Default" /v MSOSCompatIdDescriptor /t REG_BINARY /d 28000000000104000100000000000000000157494E55534200000000000000000000000000000000 /f
reg add "%F%\Configurations\Default" /v bmAttributes /t REG_DWORD /d 0x80 /f
reg add "%F%\Configurations\Default" /v bMaxPower /t REG_DWORD /d 250 /f
reg query "%F%" /s
> C:\rm9\session\fn_providers.txt echo {E98EBDBF-3058-4784-8521-47860B1D2B8E} 0xFFFFFFFFFFFFFFFF 0xFF
>> C:\rm9\session\fn_providers.txt echo {49B12C7C-4BD5-4F93-BB75-30FCE739600B} 0xFFFFFFFFFFFFFFFF 0xFF
>> C:\rm9\session\fn_providers.txt echo {569D11AA-5068-5EE5-DA22-CE541C0B1481} 0xFFFFFFFFFFFFFFFF 0xFF
logman stop rm9fn -ets
logman create trace rm9fn -pf C:\rm9\session\fn_providers.txt -o C:\rm9\session\fn.etl -f bincirc -max 32 -ets
echo [switch to function role]
reg add "%K%" /v RoleSwitchMode /t REG_DWORD /d 2 /f
pnputil /restart-device "ACPI\QCOM0C8B\0"
ping -n 21 127.0.0.1 >nul
call :status 20s
rem activate the bus: IOCTL_GENERICUSBFN_ACTIVATE_USB_BUS from a SYSTEM script; keep the handle open for ~4 minutes
start "" /b powershell -NoProfile -ExecutionPolicy Bypass -File S:\rm9\usbfn_activate.ps1 -Seconds 200
ping -n 31 127.0.0.1 >nul
call :status 50s
ping -n 61 127.0.0.1 >nul
call :status 90s
ping -n 61 127.0.0.1 >nul
call :status 150s
ping -n 61 127.0.0.1 >nul
call :status 210s
ping -n 61 127.0.0.1 >nul
call :status 270s
type C:\rm9\session\activate.txt
echo [Enum\USBFN]
reg query "HKLM\SYSTEM\CurrentControlSet\Enum\USBFN" /s
logman stop rm9fn -ets
rem back to host role before leaving
reg add "%K%" /v RoleSwitchMode /t REG_DWORD /d 1 /f
echo ==== role6 done %date% %time%
shutdown /a
shutdown /r /t 3 /f
goto :eof

:status
echo [status %1 at %time%]
powershell -NoProfile -Command "Get-PnpDevice | Where-Object { $_.InstanceId -like 'URS*' -or $_.InstanceId -like 'USBFN*' -or $_.Class -like 'UsbFn*' } | Format-Table Class,Status,FriendlyName,InstanceId -AutoSize | Out-String -Width 250"
goto :eof
