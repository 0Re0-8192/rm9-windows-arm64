@echo off
title phone-disk repair
wpeinit
set WIN=
for %%d in (C D E F G H I J K L M N O) do if exist %%d:\Windows\System32\winload.efi set WIN=%%d
echo WIN=%WIN%
if "%WIN%"=="" goto end
echo ===== chkdsk /f =====
echo Y| chkdsk %WIN%: /f
echo ===== chkdsk verify =====
chkdsk %WIN%:
echo ===== assign ESP letters =====
(echo select disk 0& echo select partition 1& echo assign letter=P) > X:\a0.txt
(echo select disk 1& echo select partition 1& echo assign letter=Q) > X:\a1.txt
(echo select disk 2& echo select partition 1& echo assign letter=R) > X:\a2.txt
(echo select disk 3& echo select partition 1& echo assign letter=S) > X:\a3.txt
for %%n in (0 1 2 3) do diskpart /s X:\a%%n.txt > nul
set ESP=
for %%e in (P Q R S) do if exist %%e:\EFI\Microsoft\Boot\bootmgfw.efi set ESP=%%e
echo ESP=%ESP%
if "%ESP%"=="" goto end
echo ===== bcdboot =====
bcdboot %WIN%:\Windows /s %ESP%: /f UEFI
echo bcdboot rc=%errorlevel%
dir %ESP%:\EFI\Microsoft\Boot\BCD
bcdedit /store %ESP%:\EFI\Microsoft\Boot\BCD /enum all
:end
echo ===== all done, shutting down =====
wpeutil shutdown
