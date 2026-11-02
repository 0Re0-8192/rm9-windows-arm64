@echo off
rem S:\rm9\run.cmd = resident PC link (linkboot).  Needs: phone_setup_loop.ps1 -Adsp -UsbFn -UsbPrep (MuChain prepares the USB PHYs) and the USBFN registry config + RoleSwitchMode=2 written by esp_run_devmode5.cmd phase 1.
rem Installs two SYSTEM boot tasks (agent = C:\rm9\link\usbfn_agent.ps1, overrides = linksnap.ps1) once (delete C:\rm9\link\installed1.flag to reinstall) and starts them.  The PC then drives the phone with refs\rm9link.py
rem (exec / put / get / reboot).  Safety: restart after 40 minutes unless the PC cancels it (rm9link exec "shutdown /a").
del S:\rm9\steps.txt
set L=C:\rm9
echo %time% step 1 >> S:\rm9\steps.txt
reg add "HKLM\SYSTEM\CurrentControlSet\Control\CrashControl" /v AutoReboot /t REG_DWORD /d 1 /f
echo %time% step 2 >> S:\rm9\steps.txt
reg add "HKLM\SYSTEM\CurrentControlSet\Control\CrashControl" /v CrashDumpEnabled /t REG_DWORD /d 3 /f
echo %time% step 3 >> S:\rm9\steps.txt
reg add "HKLM\SYSTEM\CurrentControlSet\Control\CrashControl" /v MinidumpsCount /t REG_DWORD /d 10 /f
echo %time% step 4 >> S:\rm9\steps.txt
reg add "HKLM\SYSTEM\CurrentControlSet\Services\qcwlan" /v Start /t REG_DWORD /d 4 /f
echo %time% step 5 >> S:\rm9\steps.txt
call S:\rm9\timesync.cmd
call S:\rm9\guard.cmd "" "" dppoll passive 2700
copy /y S:\rm9\dbgcap.ps1 C:\rm9\link\dbgcap.ps1 >nul 2>&1
powershell -NoProfile -ExecutionPolicy Bypass -File S:\rm9\prevcrumb.ps1
del C:\rm9\crumb.bin >nul 2>&1
echo %time% step 6 >> S:\rm9\steps.txt
if not exist C:\rm9\session mkdir C:\rm9\session
echo %time% step 7 >> S:\rm9\steps.txt
powershell -NoProfile -ExecutionPolicy Bypass -File S:\rm9\dlog.ps1 run.cmd started (linkboot)
echo %time% step 8 >> S:\rm9\steps.txt
if exist C:\rm9\disp\trial.flag if not exist C:\rm9\disp\ok.flag powershell -NoProfile -ExecutionPolicy Bypass -File S:\rm9\dispguard.ps1
echo %time% step 9 >> S:\rm9\steps.txt
reg delete "HKLM\SYSTEM\CurrentControlSet\Control\GraphicsDrivers\Configuration" /f >nul 2>&1
echo %time% step 10 >> S:\rm9\steps.txt
reg delete "HKLM\SYSTEM\CurrentControlSet\Control\GraphicsDrivers\Connectivity" /f >nul 2>&1
echo %time% step 11 >> S:\rm9\steps.txt
reg delete "HKLM\SYSTEM\CurrentControlSet\Control\GraphicsDrivers\ScaleFactors" /f >nul 2>&1
echo %time% step 12 >> S:\rm9\steps.txt
set K=HKLM\SYSTEM\CurrentControlSet\Enum\ACPI\QCOM0C8B\0\Device Parameters
echo %time% step 13 >> S:\rm9\steps.txt
reg query "%K%" /v RoleSwitchMode | find "0x2" >nul || reg add "%K%" /v RoleSwitchMode /t REG_DWORD /d 2 /f
echo %time% step 14 >> S:\rm9\steps.txt
if not exist C:\rm9\link md C:\rm9\link
echo %time% step 15 >> S:\rm9\steps.txt
copy /y S:\rm9\rm9io.ps1 C:\rm9\link\rm9io.ps1
echo %time% step 16 >> S:\rm9\steps.txt
copy /y S:\rm9\linksnap.ps1 C:\rm9\link\linksnap.ps1
echo %time% step 17 >> S:\rm9\steps.txt
if not exist C:\rm9\link\usbfn_agent.ps1 copy /y S:\rm9\usbfn_agent.ps1 C:\rm9\link\usbfn_agent.ps1
echo %time% step 18 >> S:\rm9\steps.txt
if not exist C:\rm9\link\wintun.dll copy /y S:\rm9\wintun.dll C:\rm9\link\wintun.dll
echo %time% step 19 >> S:\rm9\steps.txt
rem battery snapshot: MuChain's BattSnapshot left the ADSP battmgr values in RAM at 0xD7FF1000; read them once (the copy below overwrites any older battread.ps1)
copy /y S:\rm9\battread.ps1 C:\rm9\link\battread.ps1
echo %time% step 20 >> S:\rm9\steps.txt
powershell -NoProfile -ExecutionPolicy Bypass -File C:\rm9\link\battread.ps1 > C:\rm9\battread.txt 2>&1
echo %time% step 21 >> S:\rm9\steps.txt
rem battery probe: what does Windows make of the ACPI battery (after the PnP enumeration had time to finish)
start "" /min cmd /c "ping -n 45 127.0.0.1 >nul & call S:\rm9\battprobe.cmd"
echo %time% step 22 >> S:\rm9\steps.txt
rem user-session helpers, started from here once the desktop is up (HKLM Run / Startup folder do not fire on this build): screenshots every 15 s (C:\rm9\session\shot_n.png) and the key injector
md C:\Users\Public\rm9shot
echo %time% step 23 >> S:\rm9\steps.txt
copy /y S:\rm9\shot.ps1 C:\Users\Public\rm9shot\shot.ps1
echo %time% step 24 >> S:\rm9\steps.txt
icacls C:\Users\Public\rm9shot /grant *S-1-5-32-545:(OI)(CI)F /T
echo %time% step 25 >> S:\rm9\steps.txt
start "" /min powershell -NoProfile -ExecutionPolicy Bypass -Command "for($i=0;$i -lt 60 -and -not (Get-Process explorer -ErrorAction SilentlyContinue);$i++){Start-Sleep 2}; Start-Sleep 20; & S:\rm9\launch_in_session.ps1 -CommandLine 'powershell.exe -NoProfile -ExecutionPolicy Bypass -File C:\Users\Public\rm9shot\shot.ps1'; & S:\rm9\launch_in_session.ps1 -CommandLine 'powershell.exe -NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File C:\rm9\link\keyinject.ps1'; & S:\rm9\launch_in_session.ps1 -CommandLine 'powershell.exe -NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File C:\rm9\link\touchviz_off.ps1'"
echo %time% step 26 >> S:\rm9\steps.txt
copy /y S:\rm9\pnpdump.ps1 C:\rm9\link\pnpdump.ps1
echo %time% step 27 >> S:\rm9\steps.txt
start "" /min powershell -NoProfile -ExecutionPolicy Bypass -File C:\rm9\link\pnpdump.ps1
echo %time% step 28 >> S:\rm9\steps.txt
rem kernel DbgPrint capture (see drv\dbgcap): copy driver + client, create the service once, start it before qcwlan is enabled
copy /y S:\rm9\dbgcap.ps1 C:\rm9\link\dbgcap.ps1
echo %time% step 29 >> S:\rm9\steps.txt
rem 2026-10-30: install the dbgcap.sys from the ESP (HPPIR mode 5 SPI window); the stock dppassive run.cmd never copies it (only the cleanup stage did)
copy /y S:\rm9\dbgcap.sys C:\Windows\System32\drivers\dbgcap.sys
echo %time% step 30 >> S:\rm9\steps.txt
echo %time% step 31 >> S:\rm9\steps.txt
sc query dbgcap | find "STATE" >nul || sc create dbgcap type= kernel start= demand binPath= C:\Windows\System32\drivers\dbgcap.sys
echo %time% step 32 >> S:\rm9\steps.txt
sc config dbgcap start= demand
echo %time% step 33 >> S:\rm9\steps.txt
sc start dbgcap
echo %time% step 34 >> S:\rm9\steps.txt
sc query dbgcap > S:\rm9\dbgcap_svc.txt
echo %time% step 35 >> S:\rm9\steps.txt
rem polling build of the Wi-Fi driver (MHI event rings are processed from its SBL wait loop; the interrupts never arrive): swapped in before qcwlan can start. Delete S:\rm9\qcwlan_patched.sys to turn off.
if exist S:\rm9\qcwlan_patched.sys powershell -NoProfile -ExecutionPolicy Bypass -File S:\rm9\patchdrv.ps1
echo %time% step 36 >> S:\rm9\steps.txt
copy /y S:\rm9\rpfix.ps1 C:\rm9\link\rpfix.ps1
echo %time% step 37 >> S:\rm9\steps.txt
start "" /min powershell -NoProfile -ExecutionPolicy Bypass -File C:\rm9\link\rpfix.ps1
echo %time% step 38 >> S:\rm9\steps.txt
shutdown /a
echo %time% step 39 >> S:\rm9\steps.txt
shutdown /r /t 3000 /f
echo %time% step 40 >> S:\rm9\steps.txt
if not exist C:\rm9\link\installed1.flag (
  schtasks /create /tn rm9link /sc onstart /ru SYSTEM /rl highest /f /tr "powershell -NoProfile -ExecutionPolicy Bypass -File C:\rm9\link\usbfn_agent.ps1 -Seconds 8640000 -Log C:\rm9\link\agent.txt"
  schtasks /create /tn rm9linksnap /sc onstart /ru SYSTEM /rl highest /f /tr "powershell -NoProfile -ExecutionPolicy Bypass -File C:\rm9\link\linksnap.ps1"
  echo installed> C:\rm9\link\installed1.flag
  schtasks /run /tn rm9link
  schtasks /run /tn rm9linksnap
)
powershell -NoProfile -ExecutionPolicy Bypass -File S:\rm9\dlog.ps1 linkboot: tasks in place, agent resident
echo %time% step 41 >> S:\rm9\steps.txt
ping -n 560 127.0.0.1 >nul
echo %time% step 42 >> S:\rm9\steps.txt
