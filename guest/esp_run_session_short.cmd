@echo off
rem S:\rm9\run.cmd = interactive "session" mode: create a local console account (blank password, autologon), keep Windows up for N minutes,
rem log USB / user-session state to C:\rm9\session\ (see session.ps1), then restart cleanly.
set L=C:\rm9
call S:\rm9\timesync.cmd
echo ==== session start %date% %time%
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
rem 4. replace the 10 minute backstop by 40 minutes
shutdown /a
rem (short test: keep the 10 minute backstop from the bootstrap)
echo [accounts]
net user
powershell -NoProfile -ExecutionPolicy Bypass -File S:\rm9\session.ps1 -Seconds 200
echo ==== session done %date% %time%
shutdown /a
shutdown /r /t 3 /f
