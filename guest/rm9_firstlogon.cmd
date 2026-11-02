@echo off
rem Runs once at first logon (unattend FirstLogonCommands).  Leaves markers/logs, then RESTARTS (on the phone a power-off would need a manual power-on;
rem a restart makes Mu re-run -> watchdog -> Android, or straight back into Windows).
set L=C:\rm9
mkdir %L% 2>nul
echo firstlogon %date% %time%> %L%\firstlogon.txt
whoami>> %L%\firstlogon.txt
ver>> %L%\firstlogon.txt
mkdir %L%\panther 2>nul
xcopy /y /q %SystemRoot%\Panther\*.* %L%\panther\> nul
xcopy /y /q %SystemRoot%\System32\Sysprep\Panther\*.* %L%\panther\> nul
echo done>> %L%\firstlogon.txt
shutdown /r /t 20 /f
