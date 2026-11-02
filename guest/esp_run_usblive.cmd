@echo off
rem S:\rm9\run.cmd = live USB device-mode experiment (usblive.ps1) with the rm9io kernel driver.  Needs: RoleSwitchMode=2 + USBFN config (esp_run_role7.cmd boot 1), rm9io installed (esp_run_io.cmd).
rem Run WITHOUT -UsbFn (no pre-boot QSCRATCH overrides: the live restart of the function stack only works without them).  PC side: refs\pc_usbwatch.ps1
set L=C:\rm9
call S:\rm9\timesync.cmd
if not exist C:\rm9\session mkdir C:\rm9\session
del C:\rm9\session\usblive.txt
echo ==== usblive start %date% %time%
sc start rm9io
sc query rm9io | find "STATE"
rem a 20 minute backstop is plenty (the experiment takes ~6 minutes)
shutdown /a
shutdown /r /t 1200 /f
> C:\rm9\session\fn_providers.txt echo {E98EBDBF-3058-4784-8521-47860B1D2B8E} 0xFFFFFFFFFFFFFFFF 0xFF
>> C:\rm9\session\fn_providers.txt echo {49B12C7C-4BD5-4F93-BB75-30FCE739600B} 0xFFFFFFFFFFFFFFFF 0xFF
logman stop rm9fn -ets
logman create trace rm9fn -pf C:\rm9\session\fn_providers.txt -o C:\rm9\session\fn.etl -f bincirc -max 64 -ets
powershell -NoProfile -ExecutionPolicy Bypass -File S:\rm9\usblive.ps1
logman stop rm9fn -ets
type C:\rm9\session\usblive.txt
echo ==== usblive done %date% %time%
shutdown /a
shutdown /r /t 3 /f
