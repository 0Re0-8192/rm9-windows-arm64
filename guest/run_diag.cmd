@echo off
title phone-disk diagnostics
wpeinit
echo ===== list disk / volume =====
echo list disk> X:\dp.txt
echo list volume>> X:\dp.txt
diskpart /s X:\dp.txt
echo ===== find Windows =====
set WIN=
for %%d in (C D E F G H I J K L M N O P Q R S T U V W Y Z) do if exist %%d:\Windows\System32\winload.efi set WIN=%%d
echo WIN=%WIN%
if "%WIN%"=="" goto end
dir %WIN%:\Windows\System32\winload.efi
echo ===== chkdsk (read only) =====
chkdsk %WIN%:
:end
echo ===== done =====
