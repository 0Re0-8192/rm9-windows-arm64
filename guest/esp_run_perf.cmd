@echo off
echo ==== perf start %date% %time%
rem allow 15 minutes (the bootstrap backstop is 10 min): replace it
shutdown /a
shutdown /r /t 900 /f
powershell -NoProfile -ExecutionPolicy Bypass -File S:\rm9\perf.ps1
echo ==== perf done %date% %time%
shutdown /a
shutdown /r /t 3 /f
