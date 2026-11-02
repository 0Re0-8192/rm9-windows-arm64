@echo off
rem S:\rm9\run.cmd = read-only look at the CPU frequency hardware (EPSS) while Windows idles (about 3 minutes).  dbgcap.sys's hang/overheat guard is started first, so a freeze resets the phone within ~31 s.
rem Result: S:\rm9\epss.txt.  AutoReboot stays 1.  Compare with the Android numbers in NEXT.md.
del S:\rm9\steps.txt
echo %time% step 1 >> S:\rm9\steps.txt
reg add "HKLM\SYSTEM\CurrentControlSet\Control\CrashControl" /v AutoReboot /t REG_DWORD /d 1 /f
reg add "HKLM\SYSTEM\CurrentControlSet\Control\CrashControl" /v CrashDumpEnabled /t REG_DWORD /d 3 /f
reg add "HKLM\SYSTEM\CurrentControlSet\Services\qcwlan" /v Start /t REG_DWORD /d 4 /f
shutdown /r /t 420 /f
call S:\rm9\timesync.cmd
echo %time% step 2 >> S:\rm9\steps.txt
call S:\rm9\guard.cmd nofix
echo %time% step 3 >> S:\rm9\steps.txt
powershell -NoProfile -ExecutionPolicy Bypass -File S:\rm9\epssread.ps1
echo %time% step 4 exit=%errorlevel% >> S:\rm9\steps.txt
shutdown /a
shutdown /r /t 3 /f
