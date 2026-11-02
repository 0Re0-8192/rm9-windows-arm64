@echo off
title set SAN policy (internal disks offline)
wpeinit
set WIN=
for %%d in (C D E F G H I J K L M N O) do if exist %%d:\Windows\System32\winload.efi set WIN=%%d
echo WIN=%WIN%
if "%WIN%"=="" goto end
reg load HKLM\OFFSYS %WIN%:\Windows\System32\config\SYSTEM
echo ---- current ControlSet:
reg query HKLM\OFFSYS\Select
reg add HKLM\OFFSYS\ControlSet001\Services\partmgr\Parameters /v SanPolicy /t REG_DWORD /d 4 /f
reg query HKLM\OFFSYS\ControlSet001\Services\partmgr\Parameters
reg unload HKLM\OFFSYS
echo ---- done
:end
wpeutil shutdown
