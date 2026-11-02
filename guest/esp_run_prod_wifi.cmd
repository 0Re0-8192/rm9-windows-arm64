@echo off
rem S:\rm9\run.cmd = PRODUCTION run with interrupt-driven Wi-Fi (NEXT.md 0bl): esp_run_prod.cmd (resident PC link, ADSP battery live update, session helpers, 40 minute safety restart) + the Wi-Fi of the 0bh/0bk tests.
rem Needs: Mu-pcie-rp5 booted with run_cycle_bg.ps1 -Pcie (rm9_up.ps1 -Pcie -Touch -MuImage out\Mu-pcie-rp5.img): PCIe0 + WCN7850 left up, DSDT with RM9I0001 (rm9irq), BAT0/BCHK, MCFG/IORT.
rem ESP files: dbgcap.sys, qcwlan_patched.sys (p8), rpfix.ps1, patchdrv.ps1, dbgcap.ps1, prod.flag (rpfix: stay up), kick.flag ("5 30"), pollms.txt (1000), rpintx.flag, nocleanup.flag (keep) + everything esp_run_prod.cmd uses.
rem Windows disk: rm9irq 1.0.0.3 bound to ACPI\RM9I0001 (irqinstall.ps1 -Acpi once), Wi-Fi profile <LAB_SSID> (rpfix adds it).  Log: S:\rm9\wifi_rpfix.txt, S:\rm9\dbgcap.txt.
rem Safety: restart after 40 minutes unless the PC cancels it (rm9link exec "shutdown /a"); dbgcap's watchdog guard resets the phone when Windows hangs (no MaxRunSec here).
set L=C:\rm9
call S:\rm9\timesync.cmd
rem a bugcheck restarts by itself and leaves a minidump (an unattended phone must not sit on a blue screen)
reg add "HKLM\SYSTEM\CurrentControlSet\Control\CrashControl" /v AutoReboot /t REG_DWORD /d 1 /f >nul
reg add "HKLM\SYSTEM\CurrentControlSet\Control\CrashControl" /v CrashDumpEnabled /t REG_DWORD /d 3 /f >nul
reg add "HKLM\SYSTEM\CurrentControlSet\Control\CrashControl" /v MinidumpsCount /t REG_DWORD /d 10 /f >nul
rem the Wi-Fi driver must not start by itself: rpfix enables it once the polling build is in place and the endpoint is up
reg add "HKLM\SYSTEM\CurrentControlSet\Services\qcwlan" /v Start /t REG_DWORD /d 4 /f >nul
rem dbgcap with the ITS stall fixer (arg 1 empty), CPU cap (arg 2 empty), data-path polling (DpPoll), passive-level poll work items; no MaxRunSec
call S:\rm9\guard.cmd "" "" dppoll passive
if not exist C:\rm9\session mkdir C:\rm9\session
powershell -NoProfile -ExecutionPolicy Bypass -File S:\rm9\dlog.ps1 run.cmd started (prod wifi)
if exist C:\rm9\disp\trial.flag if not exist C:\rm9\disp\ok.flag powershell -NoProfile -ExecutionPolicy Bypass -File S:\rm9\dispguard.ps1
reg delete "HKLM\SYSTEM\CurrentControlSet\Control\GraphicsDrivers\Configuration" /f >nul 2>&1
reg delete "HKLM\SYSTEM\CurrentControlSet\Control\GraphicsDrivers\Connectivity" /f >nul 2>&1
reg delete "HKLM\SYSTEM\CurrentControlSet\Control\GraphicsDrivers\ScaleFactors" /f >nul 2>&1
set K=HKLM\SYSTEM\CurrentControlSet\Enum\ACPI\QCOM0C8B\0\Device Parameters
reg query "%K%" /v RoleSwitchMode | find "0x2" >nul || reg add "%K%" /v RoleSwitchMode /t REG_DWORD /d 2 /f
if not exist C:\rm9\link md C:\rm9\link
copy /y S:\rm9\rm9io.ps1 C:\rm9\link\rm9io.ps1
copy /y S:\rm9\linksnap.ps1 C:\rm9\link\linksnap.ps1
if not exist C:\rm9\link\usbfn_agent.ps1 copy /y S:\rm9\usbfn_agent.ps1 C:\rm9\link\usbfn_agent.ps1
if not exist C:\rm9\link\wintun.dll copy /y S:\rm9\wintun.dll C:\rm9\link\wintun.dll
rem battery snapshot: MuChain's BattSnapshot left the ADSP battmgr values in RAM at 0xD7FF1000; read them once (the copy below overwrites any older battread.ps1)
copy /y S:\rm9\battread.ps1 C:\rm9\link\battread.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File C:\rm9\link\battread.ps1 > C:\rm9\battread.txt 2>&1
rem battery probe: what does Windows make of the ACPI battery (after the PnP enumeration had time to finish)
start "" /min cmd /c "ping -n 45 127.0.0.1 >nul & call S:\rm9\battprobe.cmd"
rem battery live updater (resident, every 5 s) - log C:\rm9\battlive.log
copy /y S:\rm9\battlive.ps1 C:\rm9\link\battlive.ps1
start "" /min powershell -NoProfile -ExecutionPolicy Bypass -File C:\rm9\link\battlive.ps1 -Seconds 8640000 -Period 5
rem battery watch: what Windows sees every 60 s (C:\rm9\battwatch.txt)
copy /y S:\rm9\battwatch.ps1 C:\rm9\link\battwatch.ps1
start "" /min powershell -NoProfile -ExecutionPolicy Bypass -File C:\rm9\link\battwatch.ps1 -Seconds 8640000 -Period 60
rem user-session helpers, started from here once the desktop is up (HKLM Run / Startup folder do not fire on this build): screenshots every 15 s (C:\rm9\session\shot_n.png) and the key injector
md C:\Users\Public\rm9shot
copy /y S:\rm9\shot.ps1 C:\Users\Public\rm9shot\shot.ps1
icacls C:\Users\Public\rm9shot /grant *S-1-5-32-545:(OI)(CI)F /T
start "" /min powershell -NoProfile -ExecutionPolicy Bypass -Command "for($i=0;$i -lt 60 -and -not (Get-Process explorer -ErrorAction SilentlyContinue);$i++){Start-Sleep 2}; Start-Sleep 20; & S:\rm9\launch_in_session.ps1 -CommandLine 'powershell.exe -NoProfile -ExecutionPolicy Bypass -File C:\Users\Public\rm9shot\shot.ps1'; & S:\rm9\launch_in_session.ps1 -CommandLine 'powershell.exe -NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File C:\rm9\link\keyinject.ps1'; & S:\rm9\launch_in_session.ps1 -CommandLine 'powershell.exe -NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File C:\rm9\link\touchviz_off.ps1'"
rem Wi-Fi: polling build of the driver (swapped in before qcwlan can start; delete S:\rm9\qcwlan_patched.sys to run without), then rpfix.ps1 (prod.flag): ITS fixer, root port INTx, endpoint, qcwlan, poll + kick threads, connect, stay
copy /y S:\rm9\dbgcap.ps1 C:\rm9\link\dbgcap.ps1
if exist S:\rm9\qcwlan_patched.sys powershell -NoProfile -ExecutionPolicy Bypass -File S:\rm9\patchdrv.ps1
copy /y S:\rm9\rpfix.ps1 C:\rm9\link\rpfix.ps1
start "" /min powershell -NoProfile -ExecutionPolicy Bypass -File C:\rm9\link\rpfix.ps1
shutdown /a
shutdown /r /t 2400 /f
if not exist C:\rm9\link\installed1.flag (
  schtasks /create /tn rm9link /sc onstart /ru SYSTEM /rl highest /f /tr "powershell -NoProfile -ExecutionPolicy Bypass -File C:\rm9\link\usbfn_agent.ps1 -Seconds 8640000 -Log C:\rm9\link\agent.txt"
  schtasks /create /tn rm9linksnap /sc onstart /ru SYSTEM /rl highest /f /tr "powershell -NoProfile -ExecutionPolicy Bypass -File C:\rm9\link\linksnap.ps1"
  echo installed> C:\rm9\link\installed1.flag
  schtasks /run /tn rm9link
  schtasks /run /tn rm9linksnap
)
powershell -NoProfile -ExecutionPolicy Bypass -File S:\rm9\dlog.ps1 linkboot: tasks in place, agent resident (prod wifi)
ping -n 2300 127.0.0.1 >nul
