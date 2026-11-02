@echo off
rem S:\rm9\guard.cmd [nofix] - called near the top of every run.cmd that leaves Windows running unattended.  Loads dbgcap.sys, whose thread then
rem   (1) re-enables the GH watchdog and pings it only while every CPU runs its timer DPC and the SoC is below 100 C (a freeze resets the phone within ~31 s),
rem   (2) caps the CPU clusters through the EPSS performance-state registers (Windows has no working PPM; uncapped it idles at 85-94 C), and
rem   (3) logs the temperature every 5 s.
rem "nocap" (second argument) keeps the watchdog guard but leaves the CPU clusters alone (A/B tests).  "nofix" skips dbgcap's ITS stall fixer (two 1 ms polling threads that only the Wi-Fi bring-up needs); rpfix calls this without the argument.
rem Does nothing if dbgcap is already running (a restart would turn the watchdog off for a moment).  Never fails the caller.
if not exist C:\rm9\link md C:\rm9\link
copy /y S:\rm9\dbgcap.ps1 C:\rm9\link\dbgcap.ps1 >nul 2>&1
sc query dbgcap | find "RUNNING" >nul && goto done
copy /y S:\rm9\dbgcap.sys C:\Windows\System32\drivers\dbgcap.sys >nul 2>&1
sc query dbgcap | find "STATE" >nul || sc create dbgcap type= kernel start= demand binPath= C:\Windows\System32\drivers\dbgcap.sys
sc config dbgcap start= demand >nul 2>&1
if /i "%1"=="nofix" (reg add "HKLM\SYSTEM\CurrentControlSet\Services\dbgcap" /v NoFix /t REG_DWORD /d 1 /f >nul 2>&1) else (reg delete "HKLM\SYSTEM\CurrentControlSet\Services\dbgcap" /v NoFix /f >nul 2>&1)
if /i "%2"=="nocap" (reg add "HKLM\SYSTEM\CurrentControlSet\Services\dbgcap" /v NoCap /t REG_DWORD /d 1 /f >nul 2>&1) else (reg delete "HKLM\SYSTEM\CurrentControlSet\Services\dbgcap" /v NoCap /f >nul 2>&1)
if /i "%3"=="dppoll" (reg add "HKLM\SYSTEM\CurrentControlSet\Services\dbgcap" /v DpPoll /t REG_DWORD /d 1 /f >nul 2>&1) else (reg delete "HKLM\SYSTEM\CurrentControlSet\Services\dbgcap" /v DpPoll /f >nul 2>&1)
if /i "%4"=="passive" (reg add "HKLM\SYSTEM\CurrentControlSet\Services\dbgcap" /v PollPassive /t REG_DWORD /d 1 /f >nul 2>&1) else (reg delete "HKLM\SYSTEM\CurrentControlSet\Services\dbgcap" /v PollPassive /f >nul 2>&1)
if not "%~5"=="" (reg add "HKLM\SYSTEM\CurrentControlSet\Services\dbgcap" /v MaxRunSec /t REG_DWORD /d %~5 /f >nul 2>&1) else (reg delete "HKLM\SYSTEM\CurrentControlSet\Services\dbgcap" /v MaxRunSec /f >nul 2>&1)
rem S:\rm9\gov.flag: load-following CPU frequency governor (dbgcap Gov=1, NEXT.md 0bn) instead of the static cap.  Needs the EPSS cap to be active (not "nocap").
if exist S:\rm9\gov.flag (reg add "HKLM\SYSTEM\CurrentControlSet\Services\dbgcap" /v Gov /t REG_DWORD /d 1 /f >nul 2>&1) else (reg delete "HKLM\SYSTEM\CurrentControlSet\Services\dbgcap" /v Gov /f >nul 2>&1)
sc start dbgcap >nul 2>&1
sc query dbgcap > S:\rm9\dbgcap_svc.txt
:done
exit /b 0
