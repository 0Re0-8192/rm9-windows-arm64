@echo off
rem S:\rm9\run.cmd for the second Windows (26100 VHDX), first boots.  Windows Setup could not add the unattend account rm9 to Administrators/Users
rem (0x8007056b / net: system error 1317 "account does not exist"): the computer is named RM9 too, so the name "rm9" is read as the machine/domain, not the user.
rem Runs as LocalSystem from the rm9diag service (C:\rm9\diag.cmd).
rem   stage 1: try RM9\rm9, rename the computer (takes effect after a restart), restart
rem   stage 2: (new name) add rm9 to Administrators/Users, restart so that the auto logon takes effect
rem   stage 3: hand over to the production run.cmd (S:\rm9\run_prod.cmd = esp_run_prod_wifi.cmd: PC link, battery, Wi-Fi ...)
if not exist C:\rm9 mkdir C:\rm9
set LG=C:\rm9\acct_run2.txt
echo ===== %date% %time% run.cmd (26100 acct wrapper v2)>> %LG%
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
echo stage 3>> %LG%
net localgroup Administrators >> %LG% 2>&1
if exist S:\rm9\run_prod.cmd call S:\rm9\run_prod.cmd
