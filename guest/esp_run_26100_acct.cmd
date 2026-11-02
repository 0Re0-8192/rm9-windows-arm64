@echo off
echo %date% %time% 26100 wrapper started>> S:\rm9\w26100_run.txt
rem S:\rm9\run.cmd for the second Windows (26100 VHDX), first boots.  Windows Setup could not add the unattend account rm9 to Administrators/Users
rem (0x8007056b / net: system error 1317 "account does not exist"): the computer is named RM9 too, so the name "rm9" is read as the machine/domain, not the user.
rem Runs as LocalSystem from the rm9diag service (C:\rm9\diag.cmd).
rem   stage 1: try RM9\rm9, rename the computer (takes effect after a restart), restart
rem   stage 2: (new name) add rm9 to Administrators/Users, restart so that the auto logon takes effect
rem   stage drv: the clean image has none of the bring-up drivers: install rm9io (needed by the PC link agent), rm9irq, rm9 virtual HID, restart
rem   stage usb: write the USBFN function configuration (usbcfg.cmd, from esp_run_devmode5.cmd) + RoleSwitchMode=2, restart
rem   stage wcn: install the Wi-Fi (qcwlan) driver package from the ESP copy (wcn folder), Start=4, restart
rem   stage 3: hand over to the production run.cmd (S:\rm9\run_prod.cmd = esp_run_prod_wifi.cmd: PC link, battery, Wi-Fi ...)
if not exist C:\rm9 mkdir C:\rm9
set LG=C:\rm9\acct_run2.txt
echo ===== %date% %time% run.cmd (26100 acct wrapper v3)>> %LG%
whoami >> %LG%
echo computername=%COMPUTERNAME%>> %LG%
if not exist C:\rm9\stage2.flag (
  echo stage 1>> %LG%
  net localgroup Administrators %COMPUTERNAME%\rm9 /add >> %LG% 2>&1
  net localgroup Users %COMPUTERNAME%\rm9 /add >> %LG% 2>&1
  wmic computersystem where name="%COMPUTERNAME%" call rename name="RM9PH" >> %LG% 2>&1
  echo 1> C:\rm9\stage2.flag
  shutdown /a
  shutdown /r /t 5 /f
  exit /b 0
)
if not exist C:\rm9\stage3.flag (
  echo stage 2>> %LG%
  net localgroup Administrators rm9 /add >> %LG% 2>&1
  net localgroup Users rm9 /add >> %LG% 2>&1
  net localgroup Administrators >> %LG% 2>&1
  net user rm9 >> %LG% 2>&1
  echo 1> C:\rm9\stage3.flag
  shutdown /a
  shutdown /r /t 5 /f
  exit /b 0
)
if not exist C:\rm9\drv.flag (
  echo stage drv>> %LG%
  call S:\rm9\timesync.cmd
  certutil -addstore -f Root S:\rm9\rm9test.cer >> %LG% 2>&1
  certutil -addstore -f TrustedPublisher S:\rm9\rm9test.cer >> %LG% 2>&1
  copy /y S:\rm9\rm9io.sys C:\Windows\System32\drivers\rm9io.sys >> %LG% 2>&1
  sc query rm9io | find "STATE" >nul || sc create rm9io type= kernel start= auto binPath= C:\Windows\System32\drivers\rm9io.sys >> %LG% 2>&1
  sc config rm9io start= auto >> %LG% 2>&1
  sc start rm9io >> %LG% 2>&1
  sc query rm9io >> %LG% 2>&1
  if not exist C:\rm9\irq xcopy /e /i /y S:\rm9\irqpkg C:\rm9\irq >> %LG% 2>&1
  if not exist C:\rm9\hid xcopy /e /i /y S:\rm9\hidpkg C:\rm9\hid >> %LG% 2>&1
  copy /y S:\rm9\irqinstall.ps1 C:\rm9\irqinstall.ps1 >> %LG% 2>&1
  copy /y S:\rm9\hidinstall.ps1 C:\rm9\hidinstall.ps1 >> %LG% 2>&1
  powershell -NoProfile -ExecutionPolicy Bypass -File C:\rm9\irqinstall.ps1 -Acpi >> %LG% 2>&1
  powershell -NoProfile -ExecutionPolicy Bypass -File C:\rm9\hidinstall.ps1 >> %LG% 2>&1
  echo 1> C:\rm9\drv.flag
  shutdown /a
  shutdown /r /t 5 /f
  exit /b 0
)
if not exist C:\rm9\usb.flag (
  echo stage usb>> %LG%
  call S:\rm9\usbcfg.cmd >> %LG% 2>&1
  rem the clean image turns the display off / sleeps on its default power plan (28000 has these set): keep screen and system on
  powercfg /change monitor-timeout-ac 0 >> %LG% 2>&1
  powercfg /change monitor-timeout-dc 0 >> %LG% 2>&1
  powercfg /change standby-timeout-ac 0 >> %LG% 2>&1
  powercfg /change standby-timeout-dc 0 >> %LG% 2>&1
  powercfg /hibernate off >> %LG% 2>&1
  echo 1> C:\rm9\usb.flag
  shutdown /a
  shutdown /r /t 5 /f
  exit /b 0
)
if not exist C:\rm9\wcn.flag (
  echo stage wcn>> %LG%
  echo 1> C:\rm9\wcn.flag
  if not exist C:\rm9\wcn xcopy /e /i /y S:\rm9\wcn C:\rm9\wcn >> %LG% 2>&1
  powershell -NoProfile -ExecutionPolicy Bypass -File S:\rm9\wcn_install.ps1 >> %LG% 2>&1
  shutdown /a
  shutdown /r /t 5 /f
  exit /b 0
)
echo stage 3>> %LG%
net localgroup Administrators >> %LG% 2>&1
if exist S:\rm9\run_prod.cmd call S:\rm9\run_prod.cmd
