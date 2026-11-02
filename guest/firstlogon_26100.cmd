@echo off
rem Runs once at first logon (unattend FirstLogonCommands): marker + setup logs, then restart so the rm9diag service starts on the next boot.
set L=C:\rm9
mkdir %L% 2>nul
echo firstlogon %date% %time%> %L%\firstlogon.txt
whoami>> %L%\firstlogon.txt
ver>> %L%\firstlogon.txt
sc query rm9diag >> %L%\firstlogon.txt 2>&1
mkdir %L%\panther 2>nul
xcopy /y /q %SystemRoot%\Panther\*.* %L%\panther\> nul
xcopy /y /q %SystemRoot%\System32\Sysprep\Panther\*.* %L%\panther\> nul
echo done>> %L%\firstlogon.txt
shutdown /r /t 20 /f
