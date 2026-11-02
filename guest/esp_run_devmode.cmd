@echo off
rem S:\rm9\run.cmd = USB device (function) mode retry WITH THE ADSP UP (MuChain -Adsp: ADSP + UCSI init, no host prepare, no -UsbFn).  One boot: USBFN config + RoleSwitchMode=2, live restart of the DRD node (usblive.ps1 variants), restore the host role at the end.
rem PC side: refs\pc_usbwatch.ps1 (and the PC cable must be attached before the Mu start so that the ADSP sees the attach)
set L=C:\rm9
call S:\rm9\timesync.cmd
if not exist C:\rm9\session mkdir C:\rm9\session
del C:\rm9\session\usblive.txt
powershell -NoProfile -ExecutionPolicy Bypass -File S:\rm9\dlog.ps1 run.cmd started
copy /y S:\rm9\touchpoll.ps1 C:\rm9\touch\touchpoll.ps1
echo ==== devmode start %date% %time%
set F=HKLM\SYSTEM\CurrentControlSet\Control\USBFN
set K=HKLM\SYSTEM\CurrentControlSet\Enum\ACPI\QCOM0C8B\0\Device Parameters
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
powershell -NoProfile -ExecutionPolicy Bypass -File S:\rm9\dlog.ps1 config written, RoleSwitchMode=2
sc start rm9io
powershell -NoProfile -ExecutionPolicy Bypass -File S:\rm9\dlog.ps1 rm9io started
shutdown /a
shutdown /r /t 1500 /f
> C:\rm9\session\fn_providers.txt echo {E98EBDBF-3058-4784-8521-47860B1D2B8E} 0xFFFFFFFFFFFFFFFF 0xFF
>> C:\rm9\session\fn_providers.txt echo {49B12C7C-4BD5-4F93-BB75-30FCE739600B} 0xFFFFFFFFFFFFFFFF 0xFF
logman stop rm9fn -ets
logman create trace rm9fn -pf C:\rm9\session\fn_providers.txt -o C:\rm9\session\fn.etl -f bincirc -max 64 -ets
powershell -NoProfile -ExecutionPolicy Bypass -File S:\rm9\dlog.ps1 starting usblive
powershell -NoProfile -ExecutionPolicy Bypass -File S:\rm9\usblive.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File S:\rm9\dlog.ps1 usblive finished
logman stop rm9fn -ets
type C:\rm9\session\usblive.txt
reg add "%K%" /v RoleSwitchMode /t REG_DWORD /d 1 /f
echo ==== devmode done %date% %time%
shutdown /a
shutdown /r /t 3 /f
