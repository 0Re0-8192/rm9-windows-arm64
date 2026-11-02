@echo off
rem S:\rm9\run.cmd = USB test (22 min). Logging policy: HANDOVER.md section 0.13.  Account + autologon like esp_run_session.cmd.
set L=C:\rm9
call S:\rm9\timesync.cmd
if not exist C:\rm9\session mkdir C:\rm9\session
echo ==== usbtest start %date% %time%
net user rm9 /add /active:yes
net user rm9 ""
net localgroup Administrators rm9 /add
reg add "HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon" /v AutoAdminLogon /t REG_SZ /d 1 /f
reg add "HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon" /v DefaultUserName /t REG_SZ /d rm9 /f
reg add "HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon" /v DefaultPassword /t REG_SZ /d "" /f
reg add "HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon" /v DefaultDomainName /t REG_SZ /d %COMPUTERNAME% /f
reg add "HKLM\SOFTWARE\Policies\Microsoft\Windows\OOBE" /v DisablePrivacyExperience /t REG_DWORD /d 1 /f
powercfg /change standby-timeout-ac 0
powercfg /change monitor-timeout-ac 0
powercfg /hibernate off
rem copies the user session can read (the ESP S: is SYSTEM-only)
md C:\Users\Public\rm9shot
copy /y S:\rm9\shot.ps1 C:\Users\Public\rm9shot\shot.ps1
copy /y S:\rm9\usbhud.ps1 C:\Users\Public\rm9shot\usbhud.ps1
icacls C:\Users\Public\rm9shot /grant *S-1-5-32-545:(OI)(CI)F /T
rem ETW (circular 64 MB): USB stack + PnP
> C:\rm9\session\usb_providers.txt echo Microsoft-Windows-USB-USBXHCI 0xFFFFFFFFFFFFFFFF 0xFF
>> C:\rm9\session\usb_providers.txt echo Microsoft-Windows-USB-USBHUB3 0xFFFFFFFFFFFFFFFF 0xFF
>> C:\rm9\session\usb_providers.txt echo Microsoft-Windows-USB-UCX 0xFFFFFFFFFFFFFFFF 0xFF
>> C:\rm9\session\usb_providers.txt echo Microsoft-Windows-Kernel-PnP 0xFFFFFFFFFFFFFFFF 0xFF
logman stop rm9usb -ets
logman create trace rm9usb -pf C:\rm9\session\usb_providers.txt -o C:\rm9\session\usb.etl -f bincirc -max 64 -ets
rem backstop: 26 minutes (the test itself is 22)
shutdown /a
rem (dry run: keep the 10 minute backstop)
rem screenshots + on-screen HUD in the console user's session once the desktop is up
start "" /b powershell -NoProfile -ExecutionPolicy Bypass -Command "for($i=0;$i -lt 60 -and -not (Get-Process explorer -ErrorAction SilentlyContinue);$i++){Start-Sleep 2}; Start-Sleep 5; & S:\rm9\launch_in_session.ps1 -CommandLine 'powershell.exe -NoProfile -ExecutionPolicy Bypass -File C:\Users\Public\rm9shot\shot.ps1'; & S:\rm9\launch_in_session.ps1 -CommandLine 'powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File C:\Users\Public\rm9shot\usbhud.ps1'"
powershell -NoProfile -ExecutionPolicy Bypass -File S:\rm9\usbtest.ps1 -Seconds 300
logman stop rm9usb -ets
echo ==== usbtest done %date% %time%
shutdown /a
shutdown /r /t 3 /f
