@echo off
title RM9: add diagnostics service to the phone's Windows (offline, WinPE)
wpeinit
set PE=
for %%d in (C D E F G H I J K L M N O P Q R S T U V W Y Z) do if exist %%d:\sources\boot.wim set PE=%%d
set WIN=
for %%d in (C D E F G H I J K L M N O P Q R S T U V W Y Z) do if exist %%d:\Windows\System32\winload.efi set WIN=%%d
set LOG=%PE%:\edit.log
echo PE=%PE% WIN=%WIN% > %LOG%
if "%WIN%"=="" goto fin
rem loading the hive replays its transaction logs (SYSTEM.LOG1/LOG2), so a hive left dirty by a forced reset is handled correctly
reg load HKLM\OFFSYS %WIN%:\Windows\System32\config\SYSTEM >> %LOG% 2>&1
reg query HKLM\OFFSYS\Setup >> %LOG% 2>&1
reg add HKLM\OFFSYS\ControlSet001\Services\rm9diag /v Type /t REG_DWORD /d 16 /f >> %LOG% 2>&1
reg add HKLM\OFFSYS\ControlSet001\Services\rm9diag /v Start /t REG_DWORD /d 2 /f >> %LOG% 2>&1
reg add HKLM\OFFSYS\ControlSet001\Services\rm9diag /v ErrorControl /t REG_DWORD /d 0 /f >> %LOG% 2>&1
reg add HKLM\OFFSYS\ControlSet001\Services\rm9diag /v ImagePath /t REG_EXPAND_SZ /d "%%SystemRoot%%\System32\cmd.exe /c start \"\" /min C:\rm9\diag.cmd" /f >> %LOG% 2>&1
reg add HKLM\OFFSYS\ControlSet001\Services\rm9diag /v DisplayName /t REG_SZ /d "RM9 diagnostics" /f >> %LOG% 2>&1
reg add HKLM\OFFSYS\ControlSet001\Services\rm9diag /v ObjectName /t REG_SZ /d LocalSystem /f >> %LOG% 2>&1
reg add HKLM\OFFSYS\ControlSet001\Control\CrashControl /v CrashDumpEnabled /t REG_DWORD /d 3 /f >> %LOG% 2>&1
reg add HKLM\OFFSYS\ControlSet001\Control\CrashControl /v AutoReboot /t REG_DWORD /d 1 /f >> %LOG% 2>&1
reg add HKLM\OFFSYS\ControlSet001\Control\CrashControl /v Overwrite /t REG_DWORD /d 1 /f >> %LOG% 2>&1
reg query HKLM\OFFSYS\ControlSet001\Services\rm9diag >> %LOG% 2>&1
reg unload HKLM\OFFSYS >> %LOG% 2>&1
mkdir %WIN%:\rm9 2>nul
copy /y %PE%:\diag.cmd %WIN%:\rm9\diag.cmd >> %LOG% 2>&1
dir %WIN%:\rm9 >> %LOG% 2>&1
:fin
echo done >> %LOG%
wpeutil shutdown
