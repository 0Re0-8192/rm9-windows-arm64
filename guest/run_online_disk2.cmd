@echo off
title online every disk (does Windows rewrite a stock-layout GPT?)
wpeinit
set PE=
for %%d in (C D E F G H I J K L M N O P Q R S T U V W Y Z) do if exist %%d:\sources\boot.wim set PE=%%d
echo PE=%PE%
set LOG=%PE%:\online.log
echo ===== start > %LOG%
echo list disk> X:\dp0.txt
echo list volume>> X:\dp0.txt
diskpart /s X:\dp0.txt >> %LOG%
for %%n in (0 1 2 3) do call :one %%n
echo ===== settle 90s >> %LOG%
ping -n 90 127.0.0.1 > nul
echo list disk> X:\dp9.txt
echo list volume>> X:\dp9.txt
diskpart /s X:\dp9.txt >> %LOG%
echo ===== done >> %LOG%
wpeutil shutdown
goto :eof

:one
(echo select disk %1)> X:\dp%1.txt
(echo detail disk)>> X:\dp%1.txt
(echo online disk noerr)>> X:\dp%1.txt
(echo attributes disk clear readonly noerr)>> X:\dp%1.txt
(echo detail disk)>> X:\dp%1.txt
(echo ===== disk %1)>> %LOG%
diskpart /s X:\dp%1.txt >> %LOG%
goto :eof

