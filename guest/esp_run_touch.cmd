@echo off
rem S:\rm9\run.cmd = interactive "session" mode: create a local console account (blank password, autologon), keep Windows up for N minutes,
rem log USB / user-session state to C:\rm9\session\ (see session.ps1), then restart cleanly.
set L=C:\rm9
call S:\rm9\timesync.cmd
echo ==== session start %date% %time%
rem USB host test: the earlier function-mode experiments left RoleSwitchMode=2 (function); go back to the host role (1) and re-start the dual-role controller so the xHCI child appears
reg add "HKLM\SYSTEM\CurrentControlSet\Enum\ACPI\QCOM0C8B\0\Device Parameters" /v RoleSwitchMode /t REG_DWORD /d 1 /f
pnputil /restart-device "ACPI\QCOM0C8B\0"

rem 1. local administrator for console use. Blank password = no network logon (LimitBlankPasswordUse), no RDP/SMB exposure.
net user rm9 /add /active:yes
net user rm9 ""
net localgroup Administrators rm9 /add
reg add "HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon" /v AutoAdminLogon /t REG_SZ /d 1 /f
reg add "HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon" /v DefaultUserName /t REG_SZ /d rm9 /f
reg add "HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon" /v DefaultPassword /t REG_SZ /d "" /f
reg add "HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon" /v DefaultDomainName /t REG_SZ /d %COMPUTERNAME% /f
rem 2. no first-run experience, no sleep / screen-off while we look at it
reg add "HKLM\SOFTWARE\Policies\Microsoft\Windows\OOBE" /v DisablePrivacyExperience /t REG_DWORD /d 1 /f
powercfg /change standby-timeout-ac 0
powercfg /change monitor-timeout-ac 0
powercfg /hibernate off
rem 3. screenshot loop in the console user's own session, started from here (SYSTEM) once the desktop is up.
rem    (HKLM Run key and the Startup folder did NOT fire on this build, so launch it directly: S:\rm9\launch_in_session.ps1)
md C:\Users\Public\rm9shot
copy /y S:\rm9\shot.ps1 C:\Users\Public\rm9shot\shot.ps1
icacls C:\Users\Public\rm9shot /grant *S-1-5-32-545:(OI)(CI)F /T
powershell -NoProfile -ExecutionPolicy Bypass -Command "for($i=0;$i -lt 60 -and -not (Get-Process explorer -ErrorAction SilentlyContinue);$i++){Start-Sleep 2}; Start-Sleep 5; & S:\rm9\launch_in_session.ps1 -CommandLine 'powershell.exe -NoProfile -ExecutionPolicy Bypass -File C:\Users\Public\rm9shot\shot.ps1'"
rem 3b. touch: rm9io driver (test-signed), poller as SYSTEM (frames -> C:\Users\Public\rm9shot\touch.cur and C:\rm9\touch.log), injector in the console user's session
certutil -addstore -f Root S:\rm9\rm9test.cer
certutil -addstore -f TrustedPublisher S:\rm9\rm9test.cer
sc stop rm9io
copy /y S:\rm9\rm9io.sys C:\Windows\System32\drivers\rm9io.sys
sc query rm9io | find "STATE" >nul || sc create rm9io type= kernel start= demand binPath= C:\Windows\System32\drivers\rm9io.sys
sc start rm9io
sc query rm9io
copy /y S:\rm9\touchinject.ps1 C:\Users\Public\rm9shot\touchinject.ps1
copy /y S:\rm9\touchtest.ps1 C:\Users\Public\rm9shot\touchtest.ps1
start "" /b powershell -NoProfile -ExecutionPolicy Bypass -File S:\rm9\touchpoll.ps1 -Seconds 300
powershell -NoProfile -ExecutionPolicy Bypass -Command "for($i=0;$i -lt 60 -and -not (Get-Process explorer -ErrorAction SilentlyContinue);$i++){Start-Sleep 2}; Start-Sleep 10; & S:\rm9\launch_in_session.ps1 -CommandLine 'powershell.exe -NoProfile -ExecutionPolicy Bypass -File C:\Users\Public\rm9shot\touchtest.ps1 -Seconds 300'; & S:\rm9\launch_in_session.ps1 -CommandLine 'powershell.exe -NoProfile -ExecutionPolicy Bypass -File C:\Users\Public\rm9shot\touchinject.ps1 -Seconds 300'"
rem 4. replace the 10 minute backstop by 15 minutes (USB host test)
shutdown /a
shutdown /r /t 420 /f
echo [accounts]
net user
powershell -NoProfile -ExecutionPolicy Bypass -File S:\rm9\session.ps1 -Seconds 2100
echo ==== session done %date% %time%
shutdown /a
shutdown /r /t 3 /f
