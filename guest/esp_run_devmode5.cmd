@echo off
rem S:\rm9\run.cmd = USB device (function) mode with the remote agent (devmode5).  Like devmode2, plus: MS OS extended-property descriptor (DeviceInterfaceGUIDs) so the PC's WinUSB gets a device interface,
rem PID 0x0004 (fresh PC-side device instance). The ext-property descriptor is a per-INTERFACE value (Interfaces\GENERICUSBFN\MSOSExtendedPropertyDescriptor), found by disassembling ufx01000.sys; devmode3 put it under Configurations\ and it was ignored.
rem Phase 1 (until C:\rm9\devmode5.done exists): write the USBFN config + RoleSwitchMode=2 and restart (returns to Android).
rem Phase 2 (next start with  phone_setup_loop.ps1 -Adsp -UsbFn -UsbPrep): function role from boot, agent + usbsnap -Override.
set L=C:\rm9
call S:\rm9\timesync.cmd
if not exist C:\rm9\session mkdir C:\rm9\session
powershell -NoProfile -ExecutionPolicy Bypass -File S:\rm9\dlog.ps1 run.cmd started (devmode5)
set F=HKLM\SYSTEM\CurrentControlSet\Control\USBFN
set K=HKLM\SYSTEM\CurrentControlSet\Enum\ACPI\QCOM0C8B\0\Device Parameters
if exist C:\rm9\devmode5.done goto :phase2
for %%K in ("%F%" "%F%\Default") do (
  reg add %%K /v idVendor /t REG_DWORD /d 0x1209 /f
  reg add %%K /v idProduct /t REG_DWORD /d 0x0004 /f
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
  reg add "%F%\Configurations\%%C" /v MSOSExtendedPropertyDescriptor /t REG_BINARY /d 9200000000010500010088000000070000002A0044006500760069006300650049006E007400650072006600610063006500470055004900440073000000500000007B00440045004500380032003400450046002D0037003200390042002D0034004100300045002D0039004300310034002D004200370031003100370044003300330041003800310037007D0000000000 /f
  reg add "%F%\Configurations\%%C" /v bmAttributes /t REG_DWORD /d 0x80 /f
  reg add "%F%\Configurations\%%C" /v bMaxPower /t REG_DWORD /d 250 /f
)
reg add "%F%\Interfaces\GENERICUSBFN" /v InterfaceDescriptor /t REG_BINARY /d 0904000002FF0000000705810200020007050102000200 /f
reg add "%F%\Interfaces\GENERICUSBFN" /v InterfaceGUID /t REG_SZ /d {7a1f2c3e-5b6d-4e8f-9a0b-1c2d3e4f5a6b} /f
reg add "%F%\Interfaces\GENERICUSBFN" /v MSOSExtendedPropertyDescriptor /t REG_BINARY /d 9200000000010500010088000000070000002A0044006500760069006300650049006E007400650072006600610063006500470055004900440073000000500000007B00440045004500380032003400450046002D0037003200390042002D0034004100300045002D0039004300310034002D004200370031003100370044003300330041003800310037007D0000000000 /f
reg add "%K%" /v RoleSwitchMode /t REG_DWORD /d 2 /f
echo done> C:\rm9\devmode5.done
powershell -NoProfile -ExecutionPolicy Bypass -File S:\rm9\dlog.ps1 phase1: config written, RoleSwitchMode=2, restarting
shutdown /a
shutdown /r /t 5 /f
goto :eof
:phase2
copy /y S:\rm9\touchpoll.ps1 C:\rm9\touch\touchpoll.ps1
copy /y S:\rm9\usbfn_agent.ps1 C:\rm9\usbfn_agent.ps1
sc start rm9io
shutdown /a
shutdown /r /t 600 /f
powershell -NoProfile -ExecutionPolicy Bypass -File S:\rm9\dlog.ps1 phase2: started (function role from boot, agent)
start "" /b powershell -NoProfile -ExecutionPolicy Bypass -File C:\rm9\usbfn_agent.ps1 -Seconds 400
powershell -NoProfile -ExecutionPolicy Bypass -File S:\rm9\usbsnap.ps1 -Seconds 420 -Override
powershell -NoProfile -ExecutionPolicy Bypass -File S:\rm9\dlog.ps1 phase2: usbsnap finished
rem keep RoleSwitchMode=2 so that the next start is phase 2 again; any standard run.cmd puts the host role back
shutdown /a
shutdown /r /t 3 /f
