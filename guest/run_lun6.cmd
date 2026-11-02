@echo off
title phase1 observe only / phase2 online
wpeinit
set PE=
for %%d in (C D E F G H I J K L M N O P Q R S T U V W Y Z) do if exist %%d:\sources\boot.wim set PE=%%d
set LOG=%PE%:\ab.log
(echo ===== phase1 start)> %LOG%
time /t >> %LOG%
(echo list disk)> X:\l.txt
(echo list volume)>> X:\l.txt
diskpart /s X:\l.txt >> %LOG%
for %%n in (1 2 3 4 5 6) do call :det %%n
(echo ===== phase1 wait 150s)>> %LOG%
ping -n 150 127.0.0.1 > nul
time /t >> %LOG%
diskpart /s X:\l.txt >> %LOG%
(echo ===== phase2 online all)>> %LOG%
for %%n in (1 2 3 4 5 6) do call :on %%n
(echo ===== phase2 wait 150s)>> %LOG%
ping -n 150 127.0.0.1 > nul
time /t >> %LOG%
diskpart /s X:\l.txt >> %LOG%
for %%n in (1 2 3 4 5 6) do call :det %%n
(echo ===== done)>> %LOG%
wpeutil shutdown
goto :eof

:det
(echo select disk %1)> X:\d%1.txt
(echo detail disk)>> X:\d%1.txt
(echo ===== detail disk %1)>> %LOG%
diskpart /s X:\d%1.txt >> %LOG%
goto :eof

:on
(echo select disk %1)> X:\o%1.txt
(echo online disk noerr)>> X:\o%1.txt
(echo attributes disk clear readonly noerr)>> X:\o%1.txt
(echo ===== online disk %1)>> %LOG%
diskpart /s X:\o%1.txt >> %LOG%
goto :eof

