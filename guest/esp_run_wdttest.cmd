@echo off
rem S:\rm9\run.cmd = watchdog-guard proof (about 3 minutes).  Loads dbgcap.sys (hang/overheat guard), then wdttest.ps1 stops the pings on purpose; the hypervisor watchdog must reset the phone within ~31 s.
rem Result: S:\rm9\wdttest.txt (last line = when the reset hit) and, from the next boot's dbgcap, the crumb text.  AutoReboot stays 1.  If the guard cannot start or the reset never comes, the script ends and this file restarts Windows.
del S:\rm9\steps.txt
echo %time% step 1 >> S:\rm9\steps.txt
reg add "HKLM\SYSTEM\CurrentControlSet\Control\CrashControl" /v AutoReboot /t REG_DWORD /d 1 /f
reg add "HKLM\SYSTEM\CurrentControlSet\Control\CrashControl" /v CrashDumpEnabled /t REG_DWORD /d 3 /f
reg add "HKLM\SYSTEM\CurrentControlSet\Services\qcwlan" /v Start /t REG_DWORD /d 4 /f
shutdown /r /t 420 /f
call S:\rm9\timesync.cmd
echo %time% step 2 >> S:\rm9\steps.txt
if not exist C:\rm9\link md C:\rm9\link
copy /y S:\rm9\dbgcap.ps1 C:\rm9\link\dbgcap.ps1
sc stop dbgcap >nul 2>&1
copy /y S:\rm9\dbgcap.sys C:\Windows\System32\drivers\dbgcap.sys
sc query dbgcap | find "STATE" >nul || sc create dbgcap type= kernel start= demand binPath= C:\Windows\System32\drivers\dbgcap.sys
sc config dbgcap start= demand
sc start dbgcap
sc query dbgcap > S:\rm9\dbgcap_svc.txt
echo %time% step 3 >> S:\rm9\steps.txt
rem what the PREVIOUS boot left in DRAM (written even when that boot froze or was reset by the watchdog)
powershell -NoProfile -ExecutionPolicy Bypass -File S:\rm9\prevcrumb.ps1
echo %time% step 4 >> S:\rm9\steps.txt
powershell -NoProfile -ExecutionPolicy Bypass -File S:\rm9\wdttest.ps1
echo %time% step 5 exit=%errorlevel% >> S:\rm9\steps.txt
rem only reached when the reset did NOT happen (or the guard was off): restart now
shutdown /a
shutdown /r /t 3 /f
