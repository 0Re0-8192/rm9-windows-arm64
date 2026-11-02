@echo off
rem S:\rm9\run.cmd = resident PC link (linkboot).  Needs: phone_setup_loop.ps1 -Adsp -UsbFn -UsbPrep (MuChain prepares the USB PHYs) and the USBFN registry config + RoleSwitchMode=2 written by esp_run_devmode5.cmd phase 1.
rem Installs two SYSTEM boot tasks (agent = C:\rm9\link\usbfn_agent.ps1, overrides = linksnap.ps1) once (delete C:\rm9\link\installed1.flag to reinstall) and starts them.  The PC then drives the phone with refs\rm9link.py
rem (exec / put / get / reboot).  Safety: restart after 40 minutes unless the PC cancels it (rm9link exec "shutdown /a").
set L=C:\rm9
call S:\rm9\timesync.cmd
call S:\rm9\guard.cmd nofix
if not exist C:\rm9\session mkdir C:\rm9\session
powershell -NoProfile -ExecutionPolicy Bypass -File S:\rm9\dlog.ps1 run.cmd started (linkboot)
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
shutdown /a
shutdown /r /t 2400 /f
if not exist C:\rm9\link\installed1.flag (
  schtasks /create /tn rm9link /sc onstart /ru SYSTEM /rl highest /f /tr "powershell -NoProfile -ExecutionPolicy Bypass -File C:\rm9\link\usbfn_agent.ps1 -Seconds 8640000 -Log C:\rm9\link\agent.txt"
  schtasks /create /tn rm9linksnap /sc onstart /ru SYSTEM /rl highest /f /tr "powershell -NoProfile -ExecutionPolicy Bypass -File C:\rm9\link\linksnap.ps1"
  echo installed> C:\rm9\link\installed1.flag
  schtasks /run /tn rm9link
  schtasks /run /tn rm9linksnap
)
powershell -NoProfile -ExecutionPolicy Bypass -File S:\rm9\dlog.ps1 linkboot: tasks in place, agent resident
ping -n 2300 127.0.0.1 >nul
