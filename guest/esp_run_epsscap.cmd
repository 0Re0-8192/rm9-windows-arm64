@echo off
rem S:\rm9\run.cmd = WRITES the EPSS performance-state registers to cap the CPU frequency (lost on reboot) and watches the temperature (about 3 minutes).  dbgcap.sys's hang/overheat guard is started first, so a freeze resets the phone within ~31 s.
rem Result: S:\rm9\epsscap.txt.  AutoReboot stays 1.
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
echo %time% step 3 >> S:\rm9\steps.txt
powershell -NoProfile -ExecutionPolicy Bypass -File S:\rm9\epsscap.ps1
echo %time% step 4 exit=%errorlevel% >> S:\rm9\steps.txt
shutdown /a
shutdown /r /t 3 /f
