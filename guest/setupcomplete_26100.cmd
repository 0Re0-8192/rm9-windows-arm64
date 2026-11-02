@echo off
rem C:\Windows\Setup\Scripts\SetupComplete.cmd (runs as SYSTEM once Windows Setup/OOBE has finished): installs the rm9diag boot service that runs C:\rm9\diag.cmd on every boot.
if not exist C:\rm9 mkdir C:\rm9
echo setupcomplete %date% %time%> C:\rm9\setupcomplete.txt
sc create rm9diag binPath= "%SystemRoot%\System32\cmd.exe /c start \"\" /min C:\rm9\diag.cmd" start= auto error= ignore obj= LocalSystem DisplayName= "RM9 diagnostics" >> C:\rm9\setupcomplete.txt 2>&1
sc query rm9diag >> C:\rm9\setupcomplete.txt 2>&1
mkdir C:\rm9\panther 2>nul
xcopy /y /q %SystemRoot%\Panther\*.* C:\rm9\panther\ > nul
xcopy /y /q %SystemRoot%\System32\Sysprep\Panther\*.* C:\rm9\panther\ > nul
ver >> C:\rm9\setupcomplete.txt
echo done >> C:\rm9\setupcomplete.txt
