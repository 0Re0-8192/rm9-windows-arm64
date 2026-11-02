@echo off
rem USB test run.cmd: watch USB devices for 9 minutes (the user swaps the PC cable for OTG + USB device during that time), then restart.
echo ==== usb test start %date% %time%
rem cancel the 10 minute backstop from the bootstrap and set a 12 minute one instead
shutdown /a
shutdown /r /t 720 /f
powershell -NoProfile -ExecutionPolicy Bypass -File S:\rm9\usbwatch.ps1 -Seconds 540
echo ==== usb test done %date% %time%
shutdown /a
shutdown /r /t 3 /f
