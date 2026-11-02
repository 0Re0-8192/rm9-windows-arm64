@echo off
rem S:\rm9\timesync.cmd: the phone has no usable RTC under Windows yet (UEFI returns a fixed date).  The PC writes its local time into
rem S:\rm9\time.txt ("yyyy-MM-dd HH:mm:ss", Windows time zone is Tokyo) before every cycle; call this from run.cmd.
if exist S:\rm9\time.txt (
  for /f "usebackq tokens=*" %%t in ("S:\rm9\time.txt") do powershell -NoProfile -Command "Set-Date -Date '%%t' | Out-Null"
  echo time set from S:\rm9\time.txt: %date% %time%
)
