@echo off
rem RM9 diagnostics: runs instead of oobe\windeploy.exe (HKLM\SYSTEM\Setup\CmdLine).  Output goes to %SystemDrive%\rm9\
rem backstop: restart after 200 s even if something below hangs
shutdown /r /t 200 /f
set L=%SystemDrive%\rm9
mkdir %L% 2>nul
echo RM9 diag start %date% %time%> %L%\diag.txt
echo hello> %L%\w1.txt
if exist %L%\w1.txt (echo [1] WRITE-TEST: OK>> %L%\diag.txt) else (echo [1] WRITE-TEST: FAILED>> %L%\diag.txt)
echo [2] whoami / ver>> %L%\diag.txt
whoami>> %L%\diag.txt
ver>> %L%\diag.txt
echo [3] dirty:>> %L%\diag.txt
fsutil dirty query %SystemDrive%>> %L%\diag.txt
echo [4] disks:>> %L%\diag.txt
(echo list disk& echo list volume) > %TEMP%\rm9dp.txt
diskpart /s %TEMP%\rm9dp.txt>> %L%\diag.txt
echo [5] problem devices:>> %L%\diag.txt
pnputil /enum-devices /problem>> %L%\diag.txt
pnputil /enum-devices /connected>> %L%\diag_devices.txt
echo [6] setup logs>> %L%\diag.txt
mkdir %L%\panther 2>nul
xcopy /y /q %SystemRoot%\Panther\*.* %L%\panther\>> %L%\diag.txt
xcopy /y /q %SystemRoot%\System32\Sysprep\Panther\*.* %L%\panther\>> %L%\diag.txt
echo [7] events>> %L%\diag.txt
wevtutil qe System /c:150 /rd:true /f:text> %L%\ev_system.txt
wevtutil qe Application /c:60 /rd:true /f:text> %L%\ev_app.txt
driverquery /v /fo csv> %L%\diag_drivers.csv
echo RM9 diag done %date% %time%>> %L%\diag.txt
shutdown /a
shutdown /r /t 3 /f
